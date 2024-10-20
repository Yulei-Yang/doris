// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

#include "iceberg_reader.h"

#include <vec/core/column_with_type_and_name.h>
#include <vec/exec/format/parquet/vparquet_reader.h>

#include <vec/data_types/data_type_factory.hpp>

#include "vec/common/assert_cast.h"

namespace doris::vectorized {

const int64_t MIN_SUPPORT_DELETE_FILES_VERSION = 2;
const std::string ICEBERG_ROW_POS = "pos";

IcebergTableReader::IcebergTableReader(GenericReader* file_format_reader, RuntimeProfile* profile,
                                       RuntimeState* state, const TFileScanRangeParams& params)
        : TableFormatReader(file_format_reader), _profile(profile), _state(state), _params(params) {
    static const char* iceberg_profile = "IcebergProfile";
    ADD_TIMER(_profile, iceberg_profile);
    _iceberg_profile._delete_files_init_time =
            ADD_CHILD_TIMER(_profile, "DeleteFileInitTime", iceberg_profile);
    _iceberg_profile._delete_files_read_total_time =
            ADD_CHILD_TIMER(_profile, "DeleteFileReadTime", iceberg_profile);
}

IcebergTableReader::~IcebergTableReader() {
    if (_data_path_conjunct_ctx != nullptr) {
        _data_path_conjunct_ctx->close(_state);
    }
}

Status IcebergTableReader::get_next_block(Block* block, size_t* read_rows, bool* eof) {
    return _file_format_reader->get_next_block(block, read_rows, eof);
}

Status IcebergTableReader::set_fill_columns(
        const std::unordered_map<std::string, std::tuple<std::string, const SlotDescriptor*>>&
                partition_columns,
        const std::unordered_map<std::string, VExprContext*>& missing_columns) {
    return _file_format_reader->set_fill_columns(partition_columns, missing_columns);
}

Status IcebergTableReader::get_columns(
        std::unordered_map<std::string, TypeDescriptor>* name_to_type,
        std::unordered_set<std::string>* missing_cols) {
    return _file_format_reader->get_columns(name_to_type, missing_cols);
}

void IcebergTableReader::filter_rows(const TFileRangeDesc& range) {
    if (_cur_delete_file_reader == nullptr) {
        return;
    }
    SCOPED_TIMER(_iceberg_profile._delete_files_read_total_time);
    auto& table_desc = range.table_format_params.iceberg_params;
    auto& version = table_desc.format_version;
    if (version < MIN_SUPPORT_DELETE_FILES_VERSION) {
        return;
    }
    bool eof = false;
    std::set<RowRange> delete_row_ranges;
    while (!eof) {
        size_t read_rows = 0;
        Block block = Block();
        for (const FieldSchema& field : _column_schemas) {
            DataTypePtr data_type = DataTypeFactory::instance().create_data_type(field.type, true);
            MutableColumnPtr data_column = data_type->create_column();
            block.insert(ColumnWithTypeAndName(std::move(data_column), data_type, field.name));
        }
        Status st = _cur_delete_file_reader->get_next_block(&block, &read_rows, &eof);
        if (!st.ok() || eof) {
            if (!_delete_file_readers.empty()) {
                eof = false;
                _cur_delete_file_reader = std::move(_delete_file_readers.front());
                _delete_file_readers.pop_front();
            }
        }
        if (read_rows != 0) {
            auto& pos_type_column = block.get_by_name(ICEBERG_ROW_POS);
            ColumnPtr pos_column = pos_type_column.column;
            using ColumnType = typename PrimitiveTypeTraits<TYPE_BIGINT>::ColumnType;
            if (pos_type_column.type->is_nullable()) {
                pos_column =
                        assert_cast<const ColumnNullable&>(*pos_column).get_nested_column_ptr();
            }
            auto& data = assert_cast<const ColumnType&>(*pos_column).get_data();
            std::vector<int64_t> delete_row_ids;
            for (int row_id = 0; row_id < read_rows; row_id++) {
                delete_row_ids.emplace_back(data[row_id]);
            }
            if (delete_row_ids.empty()) {
                return;
            }

            int num_deleted_ids = delete_row_ids.size();
            int i = 0;
            while (i < num_deleted_ids) {
                int64_t row_id = delete_row_ids[i];
                int64_t row_range_start = row_id;
                int64_t row_range_end = row_id;
                while (i + 1 < num_deleted_ids) {
                    if (delete_row_ids[i + 1] == delete_row_ids[i] + 1) {
                        row_range_end = delete_row_ids[i + 1];
                        i++;
                        continue;
                    } else {
                        delete_row_ranges.emplace(row_range_start, row_range_end + 1);
                        row_range_start = ++row_range_end;
                        break;
                    }
                }
                if (i == num_deleted_ids - 1) {
                    delete_row_ranges.emplace(row_range_start,
                                              delete_row_ids[num_deleted_ids - 1] + 1);
                }
                row_range_start = delete_row_ids[i + 1];
                i++;
            }
        }
    }
    if (VLOG_IS_ON(3)) {
        if (!delete_row_ranges.empty()) {
            std::stringstream out;
            out << "[";
            for (const RowRange& delete_row_range : delete_row_ranges) {
                out << " " << delete_row_range.debug_string();
            }
            out << " ]";
            VLOG_NOTICE << "Delete row range info: " << out.str();
        }
    }
    ParquetReader* parquet_reader = (ParquetReader*)(_file_format_reader.get());
    parquet_reader->merge_delete_row_ranges(delete_row_ranges);
}

Status IcebergTableReader::init_row_filters(const TFileRangeDesc& range) {
    auto& table_desc = range.table_format_params.iceberg_params;
    auto& version = table_desc.format_version;
    if (version >= MIN_SUPPORT_DELETE_FILES_VERSION) {
        SCOPED_TIMER(_iceberg_profile._delete_files_init_time);
        auto& delete_file_type = table_desc.content;
        auto files = table_desc.delete_files;
        if (delete_file_type == POSITON_DELELE) {
            // position delete
            auto row_desc = RowDescriptor(_state->desc_tbl(),
                                          std::vector<TupleId>({table_desc.delete_table_tuple_id}),
                                          std::vector<bool>({false}));
            RETURN_IF_ERROR(VExpr::create_expr_tree(
                    _state->obj_pool(), table_desc.file_select_conjunct, &_data_path_conjunct_ctx));
            RETURN_IF_ERROR(_data_path_conjunct_ctx->prepare(_state, row_desc));
            RETURN_IF_ERROR(_data_path_conjunct_ctx->open(_state));
            vector<std::string> names;
            for (auto& delete_file : files) {
                _position_delete_params.low_bound_index = delete_file.position_lower_bound;
                _position_delete_params.upper_bound_index = delete_file.position_upper_bound;

                TFileRangeDesc delete_range;
                delete_range.path = delete_file.path;
                delete_range.start_offset = 0;
                delete_range.size = -1;
                delete_range.file_size = -1;
                ParquetReader* delete_reader = new ParquetReader(
                        _profile, _params, delete_range, _state->query_options().batch_size,
                        const_cast<cctz::time_zone*>(&_state->timezone_obj()));
                if (_delete_file_schema == nullptr) {
                    FileMetaData* metadata = nullptr;
                    RETURN_IF_ERROR(delete_reader->file_metadata(&metadata));
                    if (metadata == nullptr) {
                        break;
                    }
                    _delete_file_schema = &metadata->schema();
                    int num_of_col = _delete_file_schema->size();
                    for (auto i = 0; i < num_of_col; ++i) {
                        const FieldSchema* field = _delete_file_schema->get_column(i);
                        _column_schemas.emplace_back(*field);
                        names.emplace_back(field->name);
                    }
                }
                DCHECK_EQ(_column_schemas.size(), _delete_file_schema->size());
                // The expr assure reading delete file data from current file range only
                Status d_st =
                        delete_reader->init_reader(names, nullptr, _data_path_conjunct_ctx, false);
                std::unordered_map<std::string, std::tuple<std::string, const SlotDescriptor*>>
                        partition_columns;
                std::unordered_map<std::string, VExprContext*> missing_columns;
                delete_reader->set_fill_columns(partition_columns, missing_columns);

                _delete_file_readers.emplace_back((GenericReader*)delete_reader);

                ParquetReader* parquet_reader = (ParquetReader*)(_file_format_reader.get());
                FileMetaData* file_metadata = nullptr;
                RETURN_IF_ERROR(parquet_reader->file_metadata(&file_metadata));
                _position_delete_params.total_file_rows = file_metadata->to_thrift().num_rows;
            }
            if (!_delete_file_readers.empty()) {
                _cur_delete_file_reader = std::move(_delete_file_readers.front());
                _delete_file_readers.pop_front();
            } else {
                _cur_delete_file_reader = nullptr;
            }
        }
    }
    // todo: equality delete
    filter_rows(range);
    return Status::OK();
}

} // namespace doris::vectorized