import Foundation
import WarpCore

private final class CockroachDialect: PostgresDialect {
}

/** CockroachDB uses the Postgres wire protocol, but has a different SQL dialect and supports different features. */
public class CockroachDatabase: PostgresDatabase {
	public override var dialect: SQLDialect { return CockroachDialect() }

	override func isCompatible(_ other: PostgresDatabase) -> Bool {
		return (other is CockroachDatabase) && self.host == other.host && self.user == other.user && self.password == other.password && self.port == other.port
	}

	public override func dataForTable(_ table: String, schema: String?, job: Job, callback: (Fallible<Dataset>) -> ()) {
		switch CockroachDataset.create(database: self, tableName: table) {
		case .success(let d): callback(.success(d))
		case .failure(let e): callback(.failure(e))
		}
	}

	public override func databases(_ callback: (Fallible<[String]>) -> ()) {
		let sql = "SHOW DATABASES"
		callback(self.connect().use {
			$0.query(sql).use {(result) -> [String] in
				var dbs: [String] = []
				while let d = result.row() {
					if case .success(let infoRow) = d {
						if let name = infoRow[0].stringValue {
							dbs.append(name)
						}
					}
				}
				return dbs
			}
		})
	}

	public func tables(_ databaseName: String, callback: (Fallible<[String]>) -> ()) {
		let tc = self.dialect.tableIdentifier(databaseName, schema: nil, database: nil) // TODO: incorrect, should use something like 'databaseIdentifier'

		let sql = "SHOW TABLES FROM \(tc)"
		callback(self.connect().use {
			$0.query(sql).use { (result) -> [String] in
				var dbs: [String] = []
				while let d = result.row() {
					if case .success(let infoRow) = d {
						if let tableName = infoRow[0].stringValue {
							dbs.append(tableName)
						}
					}
				}
				return dbs
			}
		})
	}
}

/** Represents the result of a PostgreSQL query as a Dataset object. */
public class CockroachDataset: SQLDataset, PostgresWireDataset {
	private let database: CockroachDatabase

	public static func create(database: CockroachDatabase, tableName: String) -> Fallible<CockroachDataset> {
		let query = "SELECT * FROM \(database.dialect.tableIdentifier(tableName, schema: nil, database: database.database)) LIMIT 1"
		return database.connect().use {
			$0.query(query).use {(result) -> CockroachDataset in
				result.finish() // We're not interested in that one row we just requested, just the column names
				return CockroachDataset(database: database, table: tableName, columns: result.columns)
			}
		}
	}

	private init(database: CockroachDatabase, fragment: SQLFragment, columns: OrderedSet<Column>) {
		self.database = database
		super.init(fragment: fragment, columns: columns)
	}

	private init(database: CockroachDatabase, table: String, columns: OrderedSet<Column>) {
		self.database = database
		super.init(table: table, schema: nil, database: database.database, dialect: database.dialect, columns: columns)
	}

	public override func apply(_ fragment: SQLFragment, resultingColumns: OrderedSet<Column>) -> Dataset {
		return CockroachDataset(database: self.database, fragment: fragment, columns: resultingColumns)
	}

	public override func stream() -> WarpCore.Stream {
		return PostgresStream(data: self)
	}

	func result() -> Fallible<PostgresResult> {
		return database.connect().use {
			$0.query(self.sql.sqlSelect(nil).sql)
		}
	}

	override public func isCompatibleWith(_ other: SQLDataset) -> Bool {
		if let om = other as? CockroachDataset {
			if self.database.isCompatible(om.database) {
				return true
			}
		}
		return false
	}
}

public class CockroachMutableDataset: SQLMutableDataset {
	override public func identifier(_ job: Job, callback: @escaping (Fallible<Set<Column>?>) -> ()) {
		let s = self.database as! PostgresDatabase
		let tableIdentifier = s.dialect.tableIdentifier(self.tableName, schema: nil, database: s.databaseName)
		let query = "show index from \(tableIdentifier) "
		switch s.connect() {
		case .success(let connection):
			switch connection.query(query)  {
			case .success(let result):
				var primaryColumns = Set<Column>()
				for row in result {
					switch row {
					case .success(let r):
						// Row contains Table, Name ("primary"), Unique (true/false), Seq (1), Column (x)
						if let n = r[1].stringValue, n == "primary", let cn = r[4].stringValue {
							primaryColumns.insert(Column(cn))
						}
						else {
							return callback(.failure("Invalid column name received"))
						}

					case .failure(let e):
						return callback(.failure(e))
					}
				}

				if primaryColumns.count == 0 {
					return callback(.failure(NSLocalizedString("This table does not have a primary key, which is required in order to be able to identify individual rows.", comment: "")))
				}

				callback(.success(primaryColumns))

			case .failure(let e):
				return callback(.failure(e))
			}

		case .failure(let e):
			return callback(.failure(e))
		}
	}
}

