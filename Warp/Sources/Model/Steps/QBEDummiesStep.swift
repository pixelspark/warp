import Foundation
import WarpCore

class QBEDummiesTransformer: Transformer {
	let sourceColumn: Column
	let values: [Value]
	let sourceColumnFuture: Future<Fallible<OrderedSet<Column>>>
	let targetColumnFuture: Future<Fallible<OrderedSet<Column>>>

	init(source: WarpCore.Stream, sourceColumn: Column, values: [Value]) {
		self.sourceColumn = sourceColumn
		self.values = values.uniqueElements

		let sourceColumnFuture = Future<Fallible<OrderedSet<Column>>>({ (job, callback) in
			source.columns(job, callback: callback)
		})

		self.sourceColumnFuture = sourceColumnFuture

		self.targetColumnFuture = Future<Fallible<OrderedSet<Column>>>({ (job, callback) in
			sourceColumnFuture.get(job) { result in
				switch result {
				case .success(let sourceColumns):
					let newColumns = OrderedSet(values.map { QBEDummiesTransformer.nameForColumn(value: $0, sourceColumn: sourceColumn) })
					let targetColumns = sourceColumns.union(with: newColumns)
					callback(.success(targetColumns))

				case .failure(let e):
					callback(.failure(e))
				}
			}
		})

		super.init(source: source)
	}

	private static func nameForColumn(value: Value, sourceColumn: Column) -> Column {
		let s = value.stringValue ?? ""
		return Column("\(sourceColumn.name)_\(s)")
	}

	override func transform(_ rows: Array<Tuple>, streamStatus: StreamStatus, job: Job, callback: Sink) {
		self.sourceColumnFuture.get(job) { result in
			switch result {
			case .success(let sourceColumns):
				self.targetColumnFuture.get(job) { result in
					switch result {
					case .success(let targetColumns):
						let tuples = rows.map { tuple -> [Value] in
							let sourceRow = Row(tuple, columns: sourceColumns)
							var destRow = Row(columns: targetColumns)

							for sourceColumn in sourceColumns {
								destRow[sourceColumn] = sourceRow[sourceColumn]
							}

							let sourceValue = sourceRow[self.sourceColumn]
							for value in self.values {
								destRow[QBEDummiesTransformer.nameForColumn(value: value, sourceColumn: self.sourceColumn)] = Value.bool(value == sourceValue)
							}
							return destRow.values
						}
						return callback(.success(tuples), streamStatus)

					case .failure(let e):
						return callback(.failure(e), .finished)
					}
				}

			case .failure(let e):
				callback(.failure(e), .finished)
			}
		}
	}

	override func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		self.targetColumnFuture.get(job, callback)
	}

	override func clone() ->  WarpCore.Stream {
		return QBEDummiesTransformer(source: self.source.clone(), sourceColumn: self.sourceColumn, values: self.values)
	}
}

class QBEDummiesStep: QBEStep {
	var sourceColumn: Column

	required init() {
		sourceColumn = Column("")
		super.init()
	}

	init(previous: QBEStep?, sourceColumn: Column) {
		self.sourceColumn = sourceColumn
		super.init(previous: previous)
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		let sourceColumnSelector = QBESentenceDynamicOptionsToken(value: self.sourceColumn.name, provider: { [weak self] (callback) in
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
				self.sourceColumn = Column(newColumnName)
		})


		return QBESentence(format: "Create dummies from column [#]".localized,
		   sourceColumnSelector
		)
	}

	required init(coder aDecoder: NSCoder) {
		sourceColumn = Column(aDecoder.decodeString(forKey:"sourceColumn") ?? "")
		super.init(coder: aDecoder)
	}

	override func encode(with coder: NSCoder) {
		coder.encodeString(self.sourceColumn.name, forKey: "sourceColumn")
		super.encode(with: coder)
	}

	override func apply(_ data: Dataset, job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		data.unique(Sibling(self.sourceColumn), job: job) { result in
			switch result {
			case .success(let uniqueValues):
				callback(.success(StreamDataset(source: QBEDummiesTransformer(source: data.stream(), sourceColumn: self.sourceColumn, values: uniqueValues.sorted(by: { $0 < $1 })))))

			case .failure(let e):
				return callback(.failure(e))
			}
		}
	}
}
