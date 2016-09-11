# [#1] Warp won't connect to a MySQL database if it cannot find a database called 'test'

**Affects:** versions 3.0 - 3.2, **Resolved in:** version 3.3

Warp by default tries to connect to a database called 'test' when connecting to a MySQL server for the first time. If such a database does not exists, Warp will show an error, even when attempting to select another database.

**Workaround**: create a database with the name 'test' on your MySQL server(s). The database must be accessible to the user you are connecting to MySQL with from Warp. The database does not have to contain any tables.

# [#2] Warp won't be able to write to certain SQLite databases due to sandboxing restrictions

**Affects:** all versions, **Resolved in:** version 3.5

Due to sandboxing restrictions, Warp is not always able to write to SQLite databases that use journaling. Sandboxing requires Warp to obtain special permissions to write to SQLite journal files, but in some cases is unable to obtain these permissions. 

In version 3.4, SQLite databases that use journaling may in some cases not open at all. 

** Workaround**: Disable journaling for the databases (open the file using the SQLite3 command line tool or another application, and perform the following query: `PRAGMA journal_mode=DELETE;`).  You may also contact us to obtain a copy of Warp that runs outside the sandbox.