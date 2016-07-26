import Foundation
import WarpCore

class QBEExplodeVerticallyTransformer: Transformer {
	let splitColumn: Column
	let columnFuture: Future<Fallible<[Column]>>

	init(source: WarpCore.Stream, splitColumn: Column) {
		self.splitColumn = splitColumn
		self.columnFuture = Future<Fallible<[Column]>>({ (job, callback) in
			source.columns(job, callback: callback)
		})

		super.init(source: source)
	}

	override func transform(_ rows: Array<Tuple>, streamStatus: StreamStatus, job: Job, callback: Sink) {
		self.columnFuture.get(job) { result in
			switch result {
			case .success(let columns):
				let tuples = rows.flatMap { tuple -> [[Value]] in
					var row = Row(tuple, columns: columns)
					if let valueToSplit = row[self.splitColumn], let packToSplit = Pack(valueToSplit) {
						return (0..<packToSplit.count).map { index in
							let piece = packToSplit[index]
							row[self.splitColumn] = Value(piece)
							return row.values
						}
					}
					else {
						// Pass on the row verbatim
						return [tuple]
					}
				}
				return callback(.success(tuples), streamStatus)

			case .failure(let e):
				return callback(.failure(e), .finished)
			}
		}
	}

	override func clone() ->  WarpCore.Stream {
		return QBEExplodeVerticallyTransformer(source: self.source.clone(), splitColumn: self.splitColumn)
	}
}

class QBEExplodeHorizontallyTransformer: Transformer {
	let splitColumn: Column
	let separator: String
	let targetColumns: [Column]
	let sourceColumnFuture: Future<Fallible<[Column]>>
	let targetColumnFuture: Future<Fallible<[Column]>>

	init(source: WarpCore.Stream, splitColumn: Column, separator: String, targetColumns: [Column]) {
		self.splitColumn = splitColumn
		self.separator = separator
		self.targetColumns = targetColumns

		let sourceColumnFuture = Future<Fallible<[Column]>>({ (job, callback) in
			source.columns(job, callback: callback)
		})

		self.sourceColumnFuture = sourceColumnFuture

		self.targetColumnFuture = Future<Fallible<[Column]>>({ (job, callback) in
			sourceColumnFuture.get(job) { result in
				switch result {
				case .success(let sourceColumns):
					var newColumns = sourceColumns
					newColumns.remove(splitColumn)
					let addedColumns = targetColumns.filter { !newColumns.contains($0) }
					newColumns.append(contentsOf: addedColumns)
					return callback(.success(newColumns))

				case .failure(let e):
					return callback(.failure(e))
				}
			}
		})

		super.init(source: source)
	}

	override func transform(_ rows: Array<Tuple>, streamStatus: StreamStatus, job: Job, callback: Sink) {
		self.targetColumnFuture.get(job) { result in
			switch result {
			case .success(let targetColumns):
				self.sourceColumnFuture.get(job) { result in
					switch result {
					case .success(let sourceColumns):
						let tuples = rows.map { tuple -> [Value] in
							let sourceRow = Row(tuple, columns: sourceColumns)
							var destRow = Row(columns: targetColumns)

							for targetColumn in self.targetColumns {
								// TODO: pre-cache the list of columns that should be migrated over
								if sourceColumns.contains(targetColumn) {
									destRow[targetColumn] = sourceRow[targetColumn]
								}
							}

							if let valueToSplit = sourceRow[self.splitColumn], let sv = valueToSplit.stringValue {
								let parts = sv.components(separatedBy: self.separator)
								let pieceCount = min(parts.count, self.targetColumns.count)

								for index in 0..<pieceCount {
									let piece = parts[index]
									destRow[self.targetColumns[index]] = Value(piece)

								}
							}

							return destRow.values
						}
						return callback(.success(tuples), streamStatus)

					case .failure(let e):
						return callback(.failure(e), .finished)
					}
				}

			case .failure(let e):
				return callback(.failure(e), .finished)
			}
		}
	}

	override func columns(_ job: Job, callback: (Fallible<[Column]>) -> ()) {
		self.targetColumnFuture.get(job, callback)
	}

	override func clone() ->  WarpCore.Stream {
		return QBEExplodeHorizontallyTransformer(source: self.source.clone(), splitColumn: self.splitColumn, separator: self.separator, targetColumns: self.targetColumns)
	}
}

class QBEExplodeVerticallyStep: QBEStep {
	var splitColumn: Column

	required init() {
		splitColumn = Column("")
		super.init()
	}

	init(previous: QBEStep?, splitColumn: Column) {
		self.splitColumn = splitColumn
		super.init(previous: previous)
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: NSLocalizedString("Split the lists in column [#] and create a row for each item", comment: ""),
		   QBESentenceList(value: self.splitColumn.name, provider: { [weak self] (callback) in
				let job = Job(.userInitiated)
				self?.previous?.exampleDataset(job, maxInputRows: 0, maxOutputRows: 0, callback: { result in
					switch result {
					case .success(let data):
						data.columns(job) { result in
							switch result {
							case .success(let columns):
								return callback(.success(columns.map { return $0.name }))

							case .failure(let e):
								return callback(.failure(e))
							}
						}

					case .failure(let e):
						return callback(.failure(e))
					}
				})

			}, callback: { (newColumnName) in
				self.splitColumn = Column(newColumnName)
			})
		)
	}

	required init(coder aDecoder: NSCoder) {
		splitColumn = Column(aDecoder.decodeString(forKey:"splitColumn") ?? "")
		super.init(coder: aDecoder)
	}

	override func encode(with coder: NSCoder) {
		coder.encodeString(self.splitColumn.name, forKey: "splitColumn")
		super.encode(with: coder)
	}

	override func apply(_ data: Dataset, job: Job, callback: (Fallible<Dataset>) -> ()) {
		callback(.success(StreamDataset(source: QBEExplodeVerticallyTransformer(source: data.stream(), splitColumn: self.splitColumn))))
	}
}

class QBEExplodeHorizontallyStep: QBEStep {
	var separator: String
	var splitColumn: Column
	var targetColumns: [Column]

	required init() {
		separator = Pack.separator
		splitColumn = Column("")
		self.targetColumns = ["A","B","C"].map { return Column($0) }
		super.init()
	}

	init(previous: QBEStep?, splitColumn: Column, by separator: String = Pack.separator) {
		self.splitColumn = splitColumn
		self.separator = separator
		self.targetColumns = (0..<3).map { return Column(splitColumn.name + "_\($0)") }
		super.init(previous: previous)
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: "Split the values in column [#] by [#] to columns [#]".localized,
			   QBESentenceList(value: self.splitColumn.name, provider: { [weak self] (callback) in
				let job = Job(.userInitiated)
				self?.previous?.exampleDataset(job, maxInputRows: 0, maxOutputRows: 0, callback: { result in
					switch result {
					case .success(let data):
						data.columns(job) { result in
							switch result {
							case .success(let columns):
								return callback(.success(columns.map { return $0.name }))

							case .failure(let e):
								return callback(.failure(e))
							}
						}

					case .failure(let e):
						return callback(.failure(e))
					}
				})

				}, callback: { (newColumnName) in
					self.splitColumn = Column(newColumnName)
			}),
			 QBESentenceTextInput(value: self.separator, callback: { (newSeparator) -> (Bool) in
				if !newSeparator.isEmpty {
					self.separator = newSeparator
					return true
				}
				return false
			}),
			 QBESentenceColumns(value: self.targetColumns, callback: { (newColumns) in
				self.targetColumns = newColumns
			})
		)
	}

	required init(coder aDecoder: NSCoder) {
		splitColumn = Column(aDecoder.decodeString(forKey:"splitColumn") ?? "")
		separator = aDecoder.decodeString(forKey:"separator") ?? Pack.separator
		let names = (aDecoder.decodeObject(forKey: "targetColumns") as? [String]) ?? []
		self.targetColumns = names.map { return Column($0) }.uniqueElements
		super.init(coder: aDecoder)
	}

	override func encode(with coder: NSCoder) {
		let targetNames = self.targetColumns.map { return $0.name }
		coder.encodeString(self.splitColumn.name, forKey: "splitColumn")
		coder.encodeString(self.separator, forKey: "separator")
		coder.encode(targetNames, forKey: "targetColumns")
		super.encode(with: coder)
	}

	override func apply(_ data: Dataset, job: Job, callback: (Fallible<Dataset>) -> ()) {
		callback(.success(StreamDataset(source: QBEExplodeHorizontallyTransformer(source: data.stream(), splitColumn: self.splitColumn, separator: self.separator, targetColumns: self.targetColumns))))
	}
}

