/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import WarpCore
import WarpConduit

private class QBESQLiteConnection: SQLiteConnection {
	let presenters: [QBEFilePresenter]

	override init?(path: String, readOnly: Bool = false) {
		/* Writing to SQLite requires access to a journal file (usually it has the same name as the database itself, but
		with the 'sqlite-journal' file extension). In order to gain access to these 'related' files, we need to tell the
		system we are using the database. */
		if path.isEmpty {
			self.presenters = []
		}
		else {
			let url = URL(fileURLWithPath: path, isDirectory: false)
			self.presenters = ["sqlite-journal", "sqlite-shm", "sqlite-wal", "sqlite-conch"].map { return QBEFileCoordinator.sharedInstance.present(url, secondaryExtension: $0) }
		}

		super.init(path: path, readOnly: readOnly)
	}
}

private class QBESQLiteWriterSession {
	private let database: SQLiteConnection
	private let tableName: String
	private let source: Dataset

	private var job: Job? = nil
	private var stream: WarpCore.Stream?
	private var insertStatement: SQLiteResult?
	private var completion: ((Fallible<Void>) -> ())?

	init(data source: Dataset, toDatabase database: SQLiteConnection, tableName: String) {
		self.database = database
		self.tableName = tableName
		self.source = source
	}

	deinit {
		if let j = self.job {
			if j.isCancelled {
				j.log("SQLite ingest job was cancelled, rolling back transaction")
				self.database.query("ROLLBACK").require { c in
					if case .failure(let m) = c.run() {
						j.log("ROLLBACK of SQLite data failed \(m)! not swapping")
					}
				}
			}
		}
	}

	func start(_ job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		let dialect = database.dialect
		self.completion = callback
		self.job = job

		job.async {
			self.source.columns(job) { (columns) -> () in
				switch columns {
				case .success(let cns):
					if cns.isEmpty {
						return callback(.failure("Cannot cache data: data set does not contain columns".localized))
					}

					// Create SQL field specifications for the columns
					let columnSpec = cns.map({ (column) -> String in
						let colString = dialect.columnIdentifier(column, table: nil, schema: nil, database: nil)
						return "\(colString) VARCHAR"
					}).joined(separator: ", ")

					// Create destination table
					let sql = "CREATE TABLE \(dialect.tableIdentifier(self.tableName, schema: nil, database: nil)) (\(columnSpec))"
					switch self.database.query(sql) {
					case .success(let createQuery):
						if case .failure(let m) = createQuery.run() {
							return callback(.failure(m))
						}
						self.stream = self.source.stream()

						// Prepare the insert-statement
						let values = cns.map({(m) -> String in return "?"}).joined(separator: ",")
						switch self.database.query("INSERT INTO \(dialect.tableIdentifier(self.tableName, schema: nil, database: nil)) VALUES (\(values))") {
						case .success(let insertStatement):
							self.insertStatement = insertStatement
							/** SQLite inserts are fastest when they are grouped in a transaction (see docs).
							A transaction is started here and is ended in self.ingest. */
							self.database.query("BEGIN").require { r in
								if case .failure(let m) = r.run() {
									return callback(.failure(m))
								}
								// TODO: use StreamPuller to do this with more threads simultaneously
								self.stream?.fetch(job, consumer: self.ingest)
							}

						case .failure(let error):
							callback(.failure(error))
						}

					case .failure(let error):
						callback(.failure(error))
					}

				case .failure(let error):
					callback(.failure(error))
				}
			}
		}
	}

	private func ingest(_ rows: Fallible<Array<Tuple>>, streamStatus: StreamStatus) {
		switch rows {
		case .success(let r):
			if streamStatus == .hasMore && !self.job!.isCancelled {
				self.stream?.fetch(self.job!, consumer: self.ingest)
			}

			job!.time("SQLite insert", items: r.count, itemType: "rows") {
				if let statement = self.insertStatement {
					for row in r {
						if case .failure(let m) = statement.run(row) {
							self.completion!(.failure(m))
							self.completion = nil
							return
						}
					}
				}
			}

			if streamStatus == .finished {
				// First end the transaction started in init
				self.database.query("COMMIT").require { c in
					if case .failure(let m) = c.run() {
						self.job!.log("COMMIT of SQLite data failed \(m)! not swapping")
						self.completion!(.failure(m))
						self.completion = nil
						return
					}
					else {
						self.completion!(.success(()))
						self.completion = nil
					}
				}
			}

		case .failure(let errMessage):
			// Roll back the transaction that was started in init.
			self.database.query("ROLLBACK").require { c in
				if case .failure(let m) = c.run() {
					self.completion!(.failure("\(errMessage), followed by rollback failure: \(m)"))
				}
				else {
					self.completion!(.failure(errMessage))
				}
				self.completion = nil
			}
		}
	}
}

class QBESQLiteWriter: NSObject, QBEFileWriter, NSCoding {
	var tableName: String

	static func explain(_ fileExtension: String, locale: Language) -> String {
		return NSLocalizedString("SQLite database", comment: "")
	}

	static var fileTypes: Set<String> { get { return Set(["sqlite"]) } }

	required init(locale: Language, title: String?) {
		tableName = "data"
	}

	required init?(coder aDecoder: NSCoder) {
		tableName = aDecoder.decodeString(forKey:"tableName") ?? "data"
	}

	func encode(with aCoder: NSCoder) {
		aCoder.encodeString(tableName, forKey: "tableName")
	}

	func writeDataset(_ data: Dataset, toFile file: URL, locale: Language, job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		if let database = SQLiteConnection(path: file.path) {
			// We must disable the WAL because the sandbox doesn't allow us to write to the WAL file (created separately)
			database.query("PRAGMA journal_mode = MEMORY").require { s in
				if case .failure(let m) = s.run() {
					return callback(.failure(m))
				}

				database.query("DROP TABLE IF EXISTS \(database.dialect.tableIdentifier(self.tableName, schema: nil, database: nil))").require { s in
					if case .failure(let m) = s.run() {
						return callback(.failure(m))
					}
					QBESQLiteWriterSession(data: data, toDatabase: database, tableName: self.tableName).start(job, callback: callback)
				}
			}
		}
		else {
			callback(.failure(NSLocalizedString("Could not write to SQLite database file", comment: "")));
		}
	}

	func sentence(_ locale: Language) -> QBESentence? {
		return QBESentence(format: NSLocalizedString("(Over)write data to table [#]", comment: ""),
			QBESentenceTextToken(value: self.tableName, callback: { [weak self] (newTableName) -> (Bool) in
				self?.tableName = newTableName
				return true
			})
		)
	}
}

private class QBESQLiteSharedCacheDatabase {
	let connection: SQLiteConnection

	init() {
		connection = SQLiteConnection(path: "", readOnly: false)!
		/** Because this database is created anew, we can set its encoding. As the code reading strings from SQLite
		uses UTF-8, set the database's encoding to UTF-8 so that no unnecessary conversions have to take place. */

		connection.query("PRAGMA encoding = \"UTF-8\"").require { e in
			e.run().require {
				connection.query("PRAGMA synchronous = OFF").require { r in
					r.run().require {
						connection.query("PRAGMA journal_mode = MEMORY").require { s in
							s.run().require {
							}
						}
					}
				}
			}
		}
	}
}

/**
Cache a given Dataset data set in a SQLite table. Loading the data set into SQLite is performed asynchronously in the
background, and the SQLite-cached data set is swapped with the original one at completion transparently. The cache is
placed in a shared, temporary 'cache' database (sharedCacheDatabase) so that cached tables can efficiently be joined by
SQLite. Users of this class can set a completion callback if they want to wait until caching has finished. */
class QBESQLiteCachedDataset: ProxyDataset {
	private static var sharedCacheDatabase = QBESQLiteSharedCacheDatabase()

	private let database: SQLiteConnection
	private let tableName: String
	private(set) var isCached: Bool = false
	private let mutex = Mutex()
	private let cacheJob: Job
	
	init(source: Dataset, job: Job? = nil, completion: ((Fallible<QBESQLiteCachedDataset>) -> ())? = nil) {
		database = QBESQLiteCachedDataset.sharedCacheDatabase.connection
		tableName = "cache_\(String.randomStringWithLength(32))"
		self.cacheJob = job ?? Job(.background)
		super.init(data: source)
		
		QBESQLiteWriterSession(data: source, toDatabase: database, tableName: tableName).start(cacheJob) { (result) -> () in
			switch result {
			case .success:
				// Swap out the original source with our new cached source
				self.cacheJob.log("Done caching, swapping out")
				self.data.columns(self.cacheJob) { [unowned self] (columns) -> () in
					switch columns {
					case .success(let cns):
						self.mutex.locked {
							self.data = SQLiteDataset(db: self.database, fragment: SQLFragment(table: self.tableName, schema: nil, database: nil, dialect: self.database.dialect), columns: cns)
							self.isCached = true
						}
						completion?(.success(self))

					case .failure(let error):
						completion?(.failure(error))
					}
				}
			case .failure(let e):
				completion?(.failure(e))
			}
		}
	}

	deinit {
		self.mutex.locked {
			if !self.isCached {
				cacheJob.cancel()
			}
			else {
				if case .failure(let m) = self.database.query("DROP TABLE \(self.database.dialect.tableIdentifier(self.tableName, schema: nil, database: nil))") {
					trace("failure dropping table in deinitializer: \(m)")
				}
			}
		}
	}
}

/** Usually, an example data set provides a random sample of a source data set. For SQL data sets, this means that we
select randomly rows from the table. This however implies a full table scan. This class wraps around a full SQL data set
to provide an example data set where certain operations are applied to the original rather than the samples data set,
for efficiency. */
class QBESQLiteExampleDataset: ProxyDataset {
	let maxInputRows: Int
	let maxOutputRows: Int
	let fullData: Dataset

	init(data: Dataset, maxInputRows: Int, maxOutputRows: Int) {
		self.maxInputRows = maxInputRows
		self.maxOutputRows = maxOutputRows
		self.fullData = data
		super.init(data: data.random(maxInputRows))
	}

	override func unique(_ expression: Expression, job: Job, callback: @escaping (Fallible<Set<Value>>) -> ()) {
		return fullData.unique(expression, job: job, callback: callback)
	}

	override func filter(_ condition: Expression) -> Dataset {
		return fullData.filter(condition).random(max(maxInputRows, maxOutputRows))
	}
}

class QBESQLiteSourceStep: QBEStep {
	var file: QBEFileReference? = nil { didSet {
		oldValue?.url?.stopAccessingSecurityScopedResource()
		switchDatabase()
	} }
	
	var tableName: String? = nil
	private var db: SQLiteConnection? = nil

	required init() {
		super.init()
	}
	
	init?(url: URL) {
		self.file = QBEFileReference.absolute(url)
		super.init()
		switchDatabase()
	}

	init(file: QBEFileReference) {
		self.file = file
		super.init()
		switchDatabase()
	}

	deinit {
		self.file?.url?.stopAccessingSecurityScopedResource()
	}
	
	private func switchDatabase() {
		self.db = nil
		
		if let url = file?.url {
			self.db = QBESQLiteConnection(path: url.path, readOnly: true)
			
			if self.tableName == nil {
				self.db?.tableNames.maybe {(tns) in
					self.tableName = tns.first
				}
			}
		}
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		let fileSentenceItem = QBESentenceFileToken(file: self.file, allowedFileTypes: ["org.sqlite.v3"], canCreate: true, callback: { [weak self] (newFile) -> () in
			// If a file was selected that does not exist yet, create a new database
			var error: NSError? = nil
			if let url = newFile.url, !(url as NSURL).checkResourceIsReachableAndReturnError(&error) {
				let db = SQLiteDatabase(url: url as URL, readOnly: false)
				db.connect { result in
					switch result {
					case .success(_): break
					case .failure(let e):
						Swift.print("Failed to create SQLite database at \(url): \(e)")
					}
				}
			}

			self?.file = newFile
		})

		if self.file == nil {
			let template: String
			switch variant {
			case .read, .neutral: template = "Load data from SQLite database [#]"
			case .write: template = "Write to SQLite database [#]"
			}
			return QBESentence(format: NSLocalizedString(template, comment: ""), fileSentenceItem)
		}
		else {
			let template: String
			switch variant {
			case .read, .neutral: template = "Load table [#] from SQLite database [#]"
			case .write: template = "Write to table [#] in SQLite database [#]"
			}

			return QBESentence(format: NSLocalizedString(template, comment: ""),
				QBESentenceDynamicOptionsToken(value: self.tableName ?? "", provider: { [weak self] (cb) -> () in
					if let d = self?.db {
						cb(d.tableNames)
					}
				}, callback: { [weak self] (newTable) -> () in
					self?.tableName = newTable
				}),
				fileSentenceItem
			)
		}
	}
	
	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		if let d = db {
			callback(SQLiteDataset.create(d, tableName: self.tableName ?? "").use({return $0.coalesced}))
		}
		else {
			callback(.failure("The SQLite database could not be opened.".localized))
		}
	}

	override func related(job: Job, callback: @escaping (Fallible<[QBERelatedStep]>) -> ()) {
		if let d = db, let file = self.file, let tn = self.tableName, !tn.isEmpty {
			d.foreignKeys(forTable: tn, job: job) { result in
				switch result {
				case .success(let fkeys):
					let steps = fkeys.map { fkey -> QBERelatedStep in
						let s = QBESQLiteSourceStep(file: file)
						s.tableName = fkey.referencedTable
						return QBERelatedStep.joinable(step: s, type: .leftJoin, condition: Comparison(first: Sibling(Column(fkey.column)), second: Foreign(Column(fkey.referencedColumn)), type: .equal))
					}
					return callback(.success(steps))

				case .failure(let e):
					return callback(.failure(e))
				}
			}
		}
	}
	
	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: @escaping (Fallible<Dataset>) -> ()) {
		self.fullDataset(job, callback: { (fd) -> () in
			callback(fd.use {(x) -> Dataset in
				return QBESQLiteExampleDataset(data: x, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows)
			})
		})
	}
	
	required init(coder aDecoder: NSCoder) {
		self.tableName = (aDecoder.decodeObject(forKey: "tableName") as? String) ?? ""
		
		let u = aDecoder.decodeObject(forKey: "fileURL") as? URL
		let b = aDecoder.decodeObject(forKey: "fileBookmark") as? Data
		self.file = QBEFileReference.create(u, b)
		super.init(coder: aDecoder)
		
		if let url = u {
			self.db = SQLiteConnection(path: url.path, readOnly: true)
		}
	}
	
	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		coder.encode(file?.url, forKey: "fileURL")
		coder.encode(file?.bookmark, forKey: "fileBookmark")
		coder.encode(tableName, forKey: "tableName")
	}
	
	override func willSaveToDocument(_ atURL: URL) {
		self.file = self.file?.persist(atURL)
	}

	var warehouse: Warehouse? {
		if let u = self.file?.url {
			return SQLiteDatasetWarehouse(database: SQLiteDatabase(url: u, readOnly: false), schemaName: nil)
		}
		return nil
	}

	override func mutableDataset(_ job: Job, callback: @escaping (Fallible<MutableDataset>) -> ()) {
		if let u = self.file?.url, let tn = tableName {
			return callback(.success(SQLiteMutableDataset(database: SQLiteDatabase(url: u, readOnly: false), schemaName: nil, tableName: tn)))
		}
		return callback(.failure("No database opened".localized))
	}
	
	override func didLoadFromDocument(_ atURL: URL) {
		self.file = self.file?.resolve(atURL)
		if let url = self.file?.url {
			self.db = SQLiteConnection(path: url.path, readOnly: true)
		}
	}
}
