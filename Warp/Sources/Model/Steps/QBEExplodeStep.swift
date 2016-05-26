import Foundation
import WarpCore

class QBEExplodeTransformer: Transformer {
	let splitColumn: Column
	let columnFuture: Future<Fallible<[Column]>>

	init(source: Stream, splitColumn: Column) {
		self.splitColumn = splitColumn
		self.columnFuture = Future<Fallible<[Column]>>({ (job, callback) in
			source.columns(job, callback: callback)
		})

		super.init(source: source)
	}

	override func transform(rows: Array<Tuple>, streamStatus: StreamStatus, job: Job, callback: Sink) {
		self.columnFuture.get { result in
			switch result {
			case .Success(let columns):
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
				return callback(.Success(tuples), streamStatus)

			case .Failure(let e):
				return callback(.Failure(e), .Finished)
			}
		}
	}

	override func clone() -> Stream {
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

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: NSLocalizedString("Split the lists in column [#] and create a row for each item", comment: ""),
		   QBESentenceList(value: self.splitColumn.name, provider: { [weak self] (callback) in
				let job = Job(.UserInitiated)
				self?.previous?.exampleData(job, maxInputRows: 0, maxOutputRows: 0, callback: { result in
					switch result {
					case .Success(let data):
						data.columns(job) { result in
							switch result {
							case .Success(let columns):
								return callback(.Success(columns.map { return $0.name }))

							case .Failure(let e):
								return callback(.Failure(e))
							}
						}

					case .Failure(let e):
						return callback(.Failure(e))
					}
				})

			}, callback: { (newColumnName) in
				self.splitColumn = Column(newColumnName)
			})
		)
	}

	required init(coder aDecoder: NSCoder) {
		splitColumn = Column(aDecoder.decodeStringForKey("splitColumn") ?? "")
		super.init(coder: aDecoder)
	}

	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeString(self.splitColumn.name, forKey: "splitColumn")
		super.encodeWithCoder(coder)
	}

	override func apply(data: Data, job: Job, callback: (Fallible<Data>) -> ()) {
		callback(.Success(StreamData(source: QBEExplodeTransformer(source: data.stream(), splitColumn: self.splitColumn))))
	}
}