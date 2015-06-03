import Cocoa
import XCTest

class QBETests: XCTestCase {
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    } 
	
	func testStatistics() {
		var moving = QBEMoving(size: 10, items: [0,10,0,10,0,10,10,10,0,0,10,0,10,0,10,999999999999,0,5,5,5,5,5,5,5,5,5,5,5])
		XCTAssert(moving.sample.n == 10, "QBEMoving should discard old samples properly")
		XCTAssert(moving.sample.mean == 5.0, "Average of test sample should be exactly 5")
		XCTAssert(moving.sample.stdev == 0.0, "Test sample has no deviations")
		
		let (lower, upper) = moving.sample.confidenceInterval(0.90)
		XCTAssert(lower <= upper, "Test sample confidence interval must not be flipped")
		XCTAssert(lower == 5.0 && upper == 5.0, "Test sample has confidence interval that is [5,5]")
		
		// Add a value to the moving average and try again
		moving.add(100)
		XCTAssert(moving.sample.n == 10, "QBEMoving should discard old samples properly")
		XCTAssert(moving.sample.mean > 5.0, "Average of test sample should be > 5")
		XCTAssert(moving.sample.stdev > 0.0, "Test sample has a deviation now")
		let (lower2, upper2) = moving.sample.confidenceInterval(0.90)
		XCTAssert(lower2 <= upper2, "Test sample confidence interval must not be flipped")
		XCTAssert(lower2 < 5.0 && upper2 > 5.0, "Test sample has confidence interval that is wider")
		
		let (lower3, upper3) = moving.sample.confidenceInterval(0.95)
		XCTAssert(lower3 < lower2 && upper3 > upper2, "A more confident interval is wider")
	}
	
	func testQBEValue() {
		XCTAssert(QBEValue("hello") == QBEValue("hello"), "String equality")
		XCTAssert(QBEValue("hello") != QBEValue("HELLO"), "String equality is case sensitive")
		XCTAssert(QBEValue(1337) == QBEValue("1337"), "Numbers are strings")
		
		XCTAssert("Tommy".levenshteinDistance("tommy") == 1, "Levenshtein is case sensitive")
		XCTAssert("Tommy".levenshteinDistance("Tomy") == 1, "Levenshtein recognizes deletes")
		XCTAssert("Tommy".levenshteinDistance("ymmoT") == 4, "Levenshtein recognizes moves")
		XCTAssert("Tommy".levenshteinDistance("TommyV") == 1, "Levenshtein recognizes adds")
	}
	
	func testEmptyQBERaster() {
		let emptyRaster = QBERaster()
		XCTAssert(emptyRaster.rowCount == 0, "Empty raster is empty")
		XCTAssert(emptyRaster.columnCount == 0, "Empty raster is empty")
		XCTAssert(emptyRaster.columnNames.count == emptyRaster.columnCount, "Column count matches")
	}
	
	func testColumn() {
		XCTAssert(QBEColumn("Hello") == QBEColumn("hello"), "Case-insensitive column names")
		XCTAssert(QBEColumn("xxx") != QBEColumn("hello"), "Case-insensitive column names")
		
		XCTAssert(QBEColumn.defaultColumnForIndex(1337)==QBEColumn("BZL"), "Generation of column names")
		XCTAssert(QBEColumn.defaultColumnForIndex(0)==QBEColumn("A"), "Generation of column names")
		XCTAssert(QBEColumn.defaultColumnForIndex(1)==QBEColumn("B"), "Generation of column names")
	}
	
	func testArithmetic() {
		XCTAssert(QBEValue(12) * QBEValue(13) == QBEValue(156), "Integer multiplication")
		XCTAssert(QBEValue(12.2) * QBEValue(13.3) == QBEValue(162.26), "Double multiplication")
		XCTAssert(QBEValue(12) * QBEValue(13) == QBEValue(156), "Integer multiplication to double")
		XCTAssert(QBEValue("1337") & QBEValue("h4x0r") == QBEValue("1337h4x0r"), "String string concatenation")
		
		XCTAssert(QBEValue(12) / QBEValue(2) == QBEValue(6), "Integer division to double")
		XCTAssert(!(QBEValue(10.0) / QBEValue(0)).isValid, "Division by zero")
		
		XCTAssert((QBEValue(12) < QBEValue(25)) == QBEValue(true), "Less than")
		XCTAssert((QBEValue(12) > QBEValue(25)) == QBEValue(false), "Greater than")
		XCTAssert((QBEValue(12) <= QBEValue(25)) == QBEValue(true), "Less than or equal")
		XCTAssert((QBEValue(12) >= QBEValue(25)) == QBEValue(false), "Greater than or equal")
		XCTAssert((QBEValue(12) <= QBEValue(12)) == QBEValue(true), "Less than or equal")
		XCTAssert((QBEValue(12) >= QBEValue(12)) == QBEValue(true), "Greater than or equal")
		
		XCTAssert((QBEValue(12.0) == QBEValue(12)) == QBEValue(true), "Double == int")
		XCTAssert((QBEValue(12) == QBEValue(12.0)) == QBEValue(true), "Int == double")
		XCTAssert((QBEValue(12.0) != QBEValue(12)) == QBEValue(false), "Double != int")
		XCTAssert((QBEValue(12) != QBEValue(12.0)) == QBEValue(false), "Int != double")
		XCTAssert(QBEValue("12") == QBEValue(12), "String number is treated as number")
		XCTAssert((QBEValue("12") + QBEValue("13")) == QBEValue(25), "String number is treated as number")
		
		XCTAssert(QBEValue.EmptyValue == QBEValue.EmptyValue, "Empty equals empty")
		XCTAssert(QBEValue.EmptyValue != QBEValue(0), "Empty is not equal to zero")
		XCTAssert(QBEValue.EmptyValue != QBEValue(Double.NaN), "Empty is not equal to double NaN")
		XCTAssert(QBEValue.EmptyValue != QBEValue(""), "Empty is not equal to empty string")
		
		XCTAssert(!(QBEValue.InvalidValue == QBEValue.InvalidValue), "Invalid value equals nothing")
		XCTAssert(QBEValue.InvalidValue != QBEValue.InvalidValue, "Invalid value inequals other invalid value")
		
		
		XCTAssert(QBEPack("a,b,c,d").count == 4, "Pack format parser works")
		XCTAssert(QBEPack("a,b,c,d,").count == 5, "Pack format parser works")
		XCTAssert(QBEPack("a,b$0,c$1$0,d$0$1").count == 4, "Pack format parser works")
		XCTAssert(QBEPack(",").count == 2, "Pack format parser works")
		XCTAssert(QBEPack("").count == 0, "Pack format parser works")
		
		XCTAssert(QBEPack(["Tommy", "van$,der,Vorst"]).stringValue == "Tommy,van$1$0der$0Vorst", "Pack writer properly escapes")
	}
	
	func testFormulaParser() {
		let locale = QBELocale(language: QBELocale.defaultLanguage)
		
		// Test whether parsing goes right
		XCTAssert(QBEFormula(formula: "=6/ 2", locale: locale) != nil, "Parse whitespace around binary operator: right side")
		XCTAssert(QBEFormula(formula: "=6 / 2", locale: locale) != nil, "Parse whitespace around binary operator: both sides")
		XCTAssert(QBEFormula(formula: "=6 /2", locale: locale) != nil, "Parse whitespace around binary operator: left side")
		
		XCTAssert(QBEFormula(formula: "=6/(1-3/4)", locale: locale) != nil, "Formula in default dialect")
		XCTAssert(QBEFormula(formula: "6/(1-3/4)", locale: locale) == nil, "Formula needs to start with equals sign")
		XCTAssert(QBEFormula(formula: "=6/(1-3/4)±", locale: locale) == nil, "Formula needs to ignore any garbage near the end of a formula")
		XCTAssert(QBEFormula(formula: "=6/(1-3/4)+[@colRef]", locale: locale) != nil, "Formula in default dialect with column ref")
		XCTAssert(QBEFormula(formula: "=6/(1-3/4)+[@colRef]&\"stringLit\"", locale: locale) != nil, "Formula in default dialect with string literal")
		
		for ws in [" ","\t", " \t", "\r", "\n", "\r\n"] {
			XCTAssert(QBEFormula(formula: "=6\(ws)/\(ws)(\(ws)1-3/\(ws)4)", locale: locale) != nil, "Formula with whitespace '\(ws)' in between")
			XCTAssert(QBEFormula(formula: "=\(ws)6\(ws)/\(ws)(\(ws)1-3/\(ws)4)", locale: locale) != nil, "Formula with whitespace '\(ws)' after =")
			XCTAssert(QBEFormula(formula: "\(ws)=6\(ws)/\(ws)(\(ws)1-3/\(ws)4)", locale: locale) != nil, "Formula with whitespace '\(ws)' before =")
			XCTAssert(QBEFormula(formula: "=6\(ws)/\(ws)(\(ws)1-3/\(ws)4)\(ws)", locale: locale) != nil, "Formula with whitespace '\(ws)' at end")
		}
		
		// Test results
		let raster = QBERaster()
		XCTAssert(QBEFormula(formula: "=6/(1-3/4)", locale: locale)!.root.apply(QBERow(), foreign: nil, inputValue: nil) == QBEValue(24), "Formula in default dialect")
		
		// Test whether parsing goes wrong when it should
		XCTAssert(QBEFormula(formula: "", locale: locale) == nil, "Empty formula")
		XCTAssert(QBEFormula(formula: "=", locale: locale) == nil, "Empty formula with equals sign")
		XCTAssert(QBEFormula(formula: "=1+22@D@D@", locale: locale) == nil, "Garbage formula")
		

		XCTAssert(QBEFormula(formula: "=fALse", locale: locale) != nil, "Constant names should be case-insensitive")
		XCTAssert(QBEFormula(formula: "=siN(1)", locale: locale) != nil, "Function names should be case-insensitive")
	}
	
	func testExpressions() {
		XCTAssert(QBELiteralExpression(QBEValue(13.46)).isConstant, "Literal expression should be constant")
		XCTAssert(!QBEFunctionExpression(arguments: [], type: QBEFunction.RandomItem).isConstant, "Non-deterministic function expression should not be constant")
		
		XCTAssert(!QBEBinaryExpression(first: QBELiteralExpression(QBEValue(13.45)), second: QBEFunctionExpression(arguments: [], type: QBEFunction.RandomItem), type: QBEBinary.Equal).isConstant, "Binary operator applied to at least one non-constant expression should not be constant itself")
	}
	
	func testFunctions() {
		XCTAssert(QBEFunction.And.apply([QBEValue(true), QBEValue(true)]) == QBEValue(true), "AND(true, true)")
		XCTAssert(QBEFunction.And.apply([QBEValue(true), QBEValue(false)]) == QBEValue(false), "AND(true, false)")
		XCTAssert(QBEFunction.And.apply([QBEValue(false), QBEValue(false)]) == QBEValue(false), "AND(false, false)")
		
		XCTAssert(QBEFunction.Lowercase.apply([QBEValue("Tommy")]) == QBEValue("tommy"), "Lowercase")
		XCTAssert(QBEFunction.Uppercase.apply([QBEValue("Tommy")]) == QBEValue("TOMMY"), "Uppercase")
		
		XCTAssert(QBEFunction.Absolute.apply([QBEValue(-1)]) == QBEValue(1), "Absolute")
		
		XCTAssert(QBEFunction.Count.apply([]) == QBEValue(0), "Empty count returns zero")
		XCTAssert(QBEFunction.Count.apply([QBEValue(1), QBEValue(1), QBEValue.InvalidValue, QBEValue.EmptyValue]) == QBEValue(2), "Count does not include invalid values and empty values")
		XCTAssert(QBEFunction.CountAll.apply([QBEValue(1), QBEValue(1), QBEValue.InvalidValue, QBEValue.EmptyValue]) == QBEValue(4), "CountAll includes invalid values and empty values")
		
		
		// Binaries
		XCTAssert(QBEBinary.ContainsString.apply(QBEValue("Tommy"), QBEValue("om"))==QBEValue(true), "Contains string operator should be case-insensitive")
		XCTAssert(QBEBinary.ContainsString.apply(QBEValue("Tommy"), QBEValue("x"))==QBEValue(false), "Contains string operator should work")
		XCTAssert(QBEBinary.ContainsStringStrict.apply(QBEValue("Tommy"), QBEValue("Tom"))==QBEValue(true), "Strict contains string operator should work")
		XCTAssert(QBEBinary.ContainsStringStrict.apply(QBEValue("Tommy"), QBEValue("tom"))==QBEValue(false), "Strict contains string operator should be case-sensitive")
		XCTAssert(QBEBinary.ContainsStringStrict.apply(QBEValue("Tommy"), QBEValue("x"))==QBEValue(false), "Strict contains string operator should work")
		
		// Split / nth
		XCTAssert(QBEFunction.Split.apply([QBEValue("van der Vorst, Tommy"), QBEValue(" ")]).stringValue == "van,der,Vorst$0,Tommy", "Split works")
		XCTAssert(QBEFunction.Nth.apply([QBEValue("van,der,Vorst$0,Tommy"), QBEValue(3)]).stringValue == "Vorst,", "Nth works")
		XCTAssert(QBEFunction.Items.apply([QBEValue("van,der,Vorst$0,Tommy")]).intValue == 4, "Items works")
		
		// Stats
		let z = QBEFunction.NormalInverse.apply([QBEValue(0.9), QBEValue(10), QBEValue(5)]).doubleValue
		XCTAssert(z != nil, "NormalInverse should return a value under normal conditions")
		XCTAssert(z! > 16.406 && z! < 16.408, "NormalInverse should results that are equal to those of NORM.INV.N in Excel")
	}
	
	func compareData(job: QBEJob, _ a: QBEData, _ b: QBEData, callback: (Bool) -> ()) {
		a.raster(job, callback: { (aRasterFallible) -> () in
			switch aRasterFallible {
				case .Success(let aRaster):
					b.raster(job, callback: { (bRasterFallible) -> () in
						switch bRasterFallible {
							case .Success(let bRaster):
								let equal = aRaster.value.compare(bRaster.value)
								if !equal {
									job.log("A: \(aRaster.value.debugDescription)")
									job.log("B: \(bRaster.value.debugDescription)")
								}
								callback(equal)
							
							case .Failure(let error):
								XCTFail(error)
						}
					})
				
				case .Failure(let error):
					XCTFail(error)
			}
		})
	}
	
	func testCoalescer() {
		let raster = QBERaster(data: [
			[QBEValue.IntValue(1), QBEValue.IntValue(2), QBEValue.IntValue(3)],
			[QBEValue.IntValue(4), QBEValue.IntValue(5), QBEValue.IntValue(6)],
			[QBEValue.IntValue(7), QBEValue.IntValue(8), QBEValue.IntValue(9)]
		], columnNames: [QBEColumn("a"), QBEColumn("b"), QBEColumn("c")], readOnly: true)
		
		let inData = QBERasterData(raster: raster)
		let inOptData = QBECoalescedData(inData)
		let job = QBEJob(.UserInitiated)
		
		compareData(job, inData.limit(2).limit(1), inOptData.limit(2).limit(1)) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for limit(2).limit(1) should equal normal result")
		}
		
		compareData(job, inData.offset(2).offset(1), inOptData.offset(2).offset(1)) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for offset(2).offset(1) should equal normal result")
		}
		
		compareData(job, inData.offset(3), inOptData.offset(2).offset(1)) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for offset(2).offset(1) should equal offset(3)")
		}
		
		// Verify coalesced sort operations
		let aSorts = [
			QBEOrder(expression: QBESiblingExpression(columnName: "a"), ascending: true, numeric: true),
			QBEOrder(expression: QBESiblingExpression(columnName: "b"), ascending: false, numeric: true)
		]
		
		let bSorts = [
			QBEOrder(expression: QBESiblingExpression(columnName: "c"), ascending: true, numeric: true)
		]
		
		compareData(job, inData.sort(aSorts).sort(bSorts), inData.sort(bSorts + aSorts)) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for sort().sort() should equal normal result")
		}
		
		compareData(job, inData.sort(aSorts).sort(bSorts), inOptData.sort(aSorts).sort(bSorts)) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for sort().sort() should equal normal result")
		}
		
		// Verify coalesced transpose
		compareData(job, inData.transpose().transpose(), inOptData.transpose().transpose()) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for transpose().transpose() should equal normal result")
		}
		
		compareData(job, inData.transpose().transpose().transpose(), inOptData.transpose().transpose().transpose()) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for transpose().transpose().transpose() should equal normal result")
		}
		
		compareData(job, inData, inOptData.transpose().transpose()) { (equal) -> () in
			XCTAssert(equal, "Coalescer result for transpose().transpose() should equal original result")
		}
	}
	
	func testInferer() {
		let locale = QBELocale(language: QBELocale.defaultLanguage)
		var suggestions: [QBEExpression] = []
		let cols = ["A","B","C","D"].map({QBEColumn($0)})
		let row = [1,3,4,6].map({QBEValue($0)})
		QBEExpression.infer(nil, toValue: QBEValue(24), suggestions: &suggestions, level: 10, row: QBERow(row, columnNames: cols), column: 0, maxComplexity: Int.max, previousValues: [])
		suggestions.each({QBELog($0.explain(locale))})
		XCTAssert(suggestions.count>0, "Can solve the 1-3-4-6 24 game.")
	}
	
	func testQBEDataImplementations() {
		let job = QBEJob(.UserInitiated)
		
		var d: [[QBEValue]] = []
		for i in 0..<1000 {
			d.append([QBEValue(i), QBEValue(i+1), QBEValue(i+2)])
		}
		
		func assertRaster(raster: QBEFallible<QBERaster>, message: String, condition: (QBERaster) -> Bool) {
			switch raster {
				case .Success(let r):
					XCTAssertTrue(condition(r.value), message)
				
				case .Failure(let error):
					XCTFail("\(message) failed: \(error)")
			}
		}
		
		// Test the raster data implementation (the tests below are valid for all QBEData implementations)
		let data = QBERasterData(data: d, columnNames: [QBEColumn("X"), QBEColumn("Y"), QBEColumn("Z")])
		data.limit(5).raster(job) { assertRaster($0, "Limit actually works") { $0.rowCount == 5 } }
		data.offset(5).raster(job) { assertRaster($0, "Offset actually works", { $0.rowCount == 1000 - 5 }) }
		
		data.selectColumns(["THIS_DOESNT_EXIST"]).columnNames(job) { (r) -> () in
			switch r {
				case .Success(let cns):
					XCTAssert(cns.value.count == 0, "Selecting an invalid column returns a set without columns")
				
				case .Failure(let error):
					XCTFail(error)
			}
		}
		
		// Repeatedly transpose and check whether the expected number of rows and columns results
		data.raster(job) { (r) -> () in
			switch r {
				case .Success(let raster):
					let rowsBefore = raster.value.rowCount
					let columnsBefore = raster.value.columnCount
					
					self.measureBlock {
						var td: QBEData = data
						for i in 1...11 {
							td = td.transpose()
						}
						
						td.raster(job) { assertRaster($0, "Row count matches") { $0.rowCount == columnsBefore - 1 } }
						td.raster(job) { assertRaster($0, "Column count matches") { $0.columnCount == rowsBefore + 1 } }
					}
			
				case .Failure(let error):
					XCTFail(error)
			}
			
		}
		
		// Test an empty raster
		let emptyRasterData = QBERasterData(data: [], columnNames: [])
		emptyRasterData.limit(5).raster(job) { assertRaster($0, "Limit works when number of rows > available rows") { $0.rowCount == 0 } }
		emptyRasterData.selectColumns([QBEColumn("THIS_DOESNT_EXIST")]).raster(job) { assertRaster($0, "Selecting an invalid column works properly in empty raster") { $0.columnNames.count == 0 } }
	}
	
    func testQBERaster() {
		let job = QBEJob(.UserInitiated)
		
		var d: [[QBEValue]] = []
		for i in 0...1000 {
			d.append([QBEValue(i), QBEValue(i+1), QBEValue(i+2)])
		}
		
		let rasterData = QBERasterData(data: d, columnNames: [QBEColumn("X"), QBEColumn("Y"), QBEColumn("Z")])
		rasterData.raster(job) { (raster) -> () in
			switch raster {
				case .Success(let r):
					XCTAssert(r.value.indexOfColumnWithName("X")==0, "First column has index 0")
					XCTAssert(r.value.indexOfColumnWithName("x")==0, "Column names should be case-insensitive")
					XCTAssert(r.value.rowCount == 1001, "Row count matches")
					XCTAssert(r.value.columnCount == 3, "Column count matches")
				
				case .Failure(let error):
					XCTFail(error)
			}
		}
    }
	
	func testThreading() {
		let data = Array<Int>(0...5000000)
		let expectFinish = self.expectationWithDescription("Parallel map finishes in time")
		
		let future = data.parallel(
			map: { (slice: ArraySlice<Int>) -> (ArraySlice<Int>) in
				//println("Worker \(slice)")
				return slice.map({return $0 * 2})
			},
			reduce: {(s, r) -> Int in
				var greatest = r
				for number in s {
					greatest = (greatest == nil || number > greatest) ? number : greatest
				}
				return greatest ?? 0
			}
		)
		
		future.get {(result) in
			XCTAssert(result != nil && result! == 10000000, "Parallel M/R delivers the correct result")
			expectFinish.fulfill()
		}
		
		self.waitForExpectationsWithTimeout(5.0, handler: { (err) -> Void in
			if let e = err {
				println("Error=\(err)")
			}
		})
	}
}
