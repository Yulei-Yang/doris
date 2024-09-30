
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

suite("test_primary_key_partial_update_default_value", "p0") {

    String db = context.config.getDbNameByFile(context.file)
    sql "select 1;" // to create database

    for (def use_row_store : [false, true]) {
        logger.info("current params: use_row_store: ${use_row_store}")

        connect(user = context.config.jdbcUser, password = context.config.jdbcPassword, url = context.config.jdbcUrl) {
            sql "use ${db};"

            def tableName = "test_primary_key_partial_update_default_value"

            // create table
            sql """ DROP TABLE IF EXISTS ${tableName} """
            sql """ CREATE TABLE ${tableName} (
                        `id` int(11) NOT NULL COMMENT "用户 ID",
                        `name` varchar(65533) NOT NULL DEFAULT "yixiu" COMMENT "用户姓名",
                        `score` int(11) NOT NULL COMMENT "用户得分",
                        `test` int(11) NULL DEFAULT "4321" COMMENT  "test",
                        `dft` int(11) DEFAULT "4321")
                        UNIQUE KEY(`id`)
                        CLUSTER BY(`name`, `score`) 
                        DISTRIBUTED BY HASH(`id`) BUCKETS 1
                        PROPERTIES("replication_num" = "1", "enable_unique_key_merge_on_write" = "true",
                        "store_row_column" = "${use_row_store}"); """
            // insert 2 lines
            sql """
                insert into ${tableName} values(2, "doris2", 2000, 223, 1)
            """

            sql """
                insert into ${tableName} values(1, "doris", 1000, 123, 1)
            """

            // stream load with key not exit before
            streamLoad {
                table "${tableName}"

                set 'column_separator', ','
                set 'format', 'csv'
                set 'partial_columns', 'true'
                set 'columns', 'id,score'

                file 'default.csv'
                time 10000 // limit inflight 10s

                check { result, exception, startTime, endTime ->
                    if (exception != null) {
                        throw exception
                    }
                    log.info("Stream load result: ${result}".toString())
                    def json = parseJson(result)
                    txnId = json.TxnId
                    assertEquals("fail", json.Status.toLowerCase())
                    assertTrue(json.Message.contains("Can't do partial update on merge-on-write Unique table with cluster keys"))
                }
            }

            sql "sync"

            qt_select_default """
                select * from ${tableName} order by id;
            """

            // drop drop
            sql """ DROP TABLE IF EXISTS ${tableName} """
        }
    }
}
