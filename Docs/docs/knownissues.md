# [#1] Warp won't connect to a MySQL database if it cannot find a database called 'test'

**Affects:** versions 3.0 - 3.2, **Resolved in:** version 3.3

Warp by default tries to connect to a database called 'test' when connecting to a MySQL server for the first time. If such a database does not exists, Warp will show an error, even when attempting to select another database.

**Workaround**: create a database with the name 'test' on your MySQL server(s). The database must be accessible to the user you are connecting to MySQL with from Warp. The database does not have to contain any tables.

# [#2] Warp won't be able to write to certain SQLite databases due to sandboxing restrictions

**Affects:** all versions

Due to sandboxing restrictions, Warp is not always able to write to SQLite databases that use journaling. Sandboxing requires Warp to obtain special permissions to write to SQLite journal files, but in some cases is unable to obtain these permissions. 

** Workaround**: Disable journaling for the databases, or try to re-open the database using the 'Load data from file' command from the 'File' menu in Warp. You may also contact us to obtain a copy of Warp that runs outside the sandbox.