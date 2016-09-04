/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import WarpCore

class QBEExplodeVerticallyTransformer: Transformer {
	let splitColumn: Column
	let separator: String? // If nil, separation happens using Pack (lists)
	let columnFuture: Future<Fallible<OrderedSet<Column>>>

	init(source: WarpCore.Stream, splitColumn: Column, separator: String?) {
		self.splitColumn = splitColumn
		self.separator = separator
		self.columnFuture = Future<Fallible<OrderedSet<Column>>>({ (job, callback) in
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
					if let valueToSplit = row[self.splitColumn] {
						let pieces: [String]
						if let s = self.separator {
							pieces = valueToSplit.stringValue?.components(separatedBy: s) ?? []
						}
						else {
							pieces = Pack(valueToSplit)?.items ?? []
						}

						return (0..<pieces.count).map { index in
							let piece = pieces[index]
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
		return QBEExplodeVerticallyTransformer(source: self.source.clone(), splitColumn: self.splitColumn, separator: self.separator)
	}
}

class QBEExplodeHorizontallyTransformer: Transformer {
	let splitColumn: Column
	let separator: String
	let targetColumns: OrderedSet<Column>
	let sourceColumnFuture: Future<Fallible<OrderedSet<Column>>>
	let targetColumnFuture: Future<Fallible<OrderedSet<Column>>>

	init(source: WarpCore.Stream, splitColumn: Column, separator: String, targetColumns: OrderedSet<Column>) {
		self.splitColumn = splitColumn
		self.separator = separator
		self.targetColumns = targetColumns

		let sourceColumnFuture = Future<Fallible<OrderedSet<Column>>>({ (job, callback) in
			source.columns(job, callback: callback)
		})

		self.sourceColumnFuture = sourceColumnFuture

		self.targetColumnFuture = Future<Fallible<OrderedSet<Column>>>({ (job, callback) in
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

	override func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		self.targetColumnFuture.get(job, callback)
	}

	override func clone() ->  WarpCore.Stream {
		return QBEExplodeHorizontallyTransformer(source: self.source.clone(), splitColumn: self.splitColumn, separator: self.separator, targetColumns: self.targetColumns)
	}
}

class QBEExplodeVerticallyStep: QBEStep {
	var splitColumn: Column
	var separator: String? = nil // If nil, separation happens using Pack (lists)

	required init() {
		splitColumn = Column("")
		super.init()
	}

	init(previous: QBEStep?, splitColumn: Column) {
		self.splitColumn = splitColumn
		super.init(previous: previous)
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		let modeSelector = QBESentenceOptionsToken(options: ["pack": "lists".localized, "separator": "values by separator".localized], value: self.separator == nil ? "pack" : "separator") { (newMode) in
			if newMode == "pack" {
				self.separator = nil
			}
			else {
				self.separator = Pack.separator
			}
		}

		let sourceColumnSelector = QBESentenceDynamicOptionsToken(value: self.splitColumn.name, provider: { [weak self] (callback) in
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

		let separatorSelector = QBESentenceTextToken(value: self.separator ?? Pack.separator) { (newSeparator) -> (Bool) in
			if !newSeparator.isEmpty {
				self.separator = newSeparator
				return true
			}
			return false
		}

		if self.separator == nil {
			return QBESentence(format: "Split [#] in column [#] and create a row for each item".localized,
				modeSelector,
				sourceColumnSelector
			)
		}
		else {
			return QBESentence(format: "Split [#] [#] in column [#] and create a row for each item".localized,
			   modeSelector,
			   separatorSelector,
			   sourceColumnSelector
			)
		}
	}

	required init(coder aDecoder: NSCoder) {
		splitColumn = Column(aDecoder.decodeString(forKey:"splitColumn") ?? "")
		separator = aDecoder.decodeString(forKey: "separator")
		super.init(coder: aDecoder)
	}

	override func encode(with coder: NSCoder) {
		coder.encodeString(self.splitColumn.name, forKey: "splitColumn")
		if let s = self.separator {
			coder.encodeString(s, forKey: "separator")
		}
		super.encode(with: coder)
	}

	override func apply(_ data: Dataset, job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		callback(.success(StreamDataset(source: QBEExplodeVerticallyTransformer(source: data.stream(), splitColumn: self.splitColumn, separator: self.separator))))
	}
}

class QBEExplodeHorizontallyStep: QBEStep {
	var separator: String
	var splitColumn: Column
	var targetColumns: OrderedSet<Column>

	required init() {
		separator = Pack.separator
		splitColumn = Column("")
		self.targetColumns = OrderedSet(["A","B","C"].map { return Column($0) })
		super.init()
	}

	init(previous: QBEStep?, splitColumn: Column, by separator: String = Pack.separator) {
		self.splitColumn = splitColumn
		self.separator = separator
		self.targetColumns = OrderedSet((0..<3).map { return Column(splitColumn.name + "_\($0)") })
		super.init(previous: previous)
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: "Split the values in column [#] by [#] to columns [#]".localized,
			   QBESentenceDynamicOptionsToken(value: self.splitColumn.name, provider: { [weak self] (callback) in
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
			 QBESentenceTextToken(value: self.separator, callback: { (newSeparator) -> (Bool) in
				if !newSeparator.isEmpty {
					self.separator = newSeparator
					return true
				}
				return false
			}),
			 QBESentenceColumnsToken(value: self.targetColumns, callback: { (newColumns) in
				self.targetColumns = newColumns
			})
		)
	}

	required init(coder aDecoder: NSCoder) {
		splitColumn = Column(aDecoder.decodeString(forKey:"splitColumn") ?? "")
		separator = aDecoder.decodeString(forKey:"separator") ?? Pack.separator
		let names = (aDecoder.decodeObject(forKey: "targetColumns") as? [String]) ?? []
		self.targetColumns = OrderedSet<Column>(names.map { return Column($0) }.uniqueElements)
		super.init(coder: aDecoder)
	}

	override func encode(with coder: NSCoder) {
		let targetNames = self.targetColumns.map { return $0.name }
		coder.encodeString(self.splitColumn.name, forKey: "splitColumn")
		coder.encodeString(self.separator, forKey: "separator")
		coder.encode(targetNames, forKey: "targetColumns")
		super.encode(with: coder)
	}

	override func apply(_ data: Dataset, job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		callback(.success(StreamDataset(source: QBEExplodeHorizontallyTransformer(source: data.stream(), splitColumn: self.splitColumn, separator: self.separator, targetColumns: self.targetColumns))))
	}
}

