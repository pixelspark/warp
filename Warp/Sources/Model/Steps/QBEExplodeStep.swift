import Foundation
import WarpCore

class QBEExplodeTransformer: Transformer {
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
		self.columnFuture.get { result in
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
		return QBEExplodeTransformer(source: self.source.clone(), splitColumn: self.splitColumn)
	}
}

class QBEExplodeStep: QBEStep {
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
		callback(.success(StreamDataset(source: QBEExplodeTransformer(source: data.stream(), splitColumn: self.splitColumn))))
	}
}
