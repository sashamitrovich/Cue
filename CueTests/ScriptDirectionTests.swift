import XCTest
@testable import Cue

/// #20: the prompter has to know a script reads right to left, from the
/// script itself. These are the cases a real reader produces, not just the
/// clean ones.
final class ScriptDirectionTests: XCTestCase {

    func testArabicIsRightToLeft() {
        XCTAssertTrue(ScriptDirection.isRightToLeft("النصيحة الأولى هي أن تتنفس قبل أن تبدأ."))
    }

    func testHebrewIsRightToLeft() {
        XCTAssertTrue(ScriptDirection.isRightToLeft("שלום לכולם, היום שלושה טיפים פשוטים."))
    }

    func testPersianAndUrduAreRightToLeft() {
        XCTAssertTrue(ScriptDirection.isRightToLeft("سلام به همه، امروز سه نکته ساده دارم."))
        XCTAssertTrue(ScriptDirection.isRightToLeft("سب کو سلام، آج میرے پاس تین آسان مشورے ہیں۔"))
    }

    func testArabicWithDiacriticsStaysRightToLeft() {
        // Tashkeel are combining marks; they must not tip the count either way.
        XCTAssertTrue(ScriptDirection.isRightToLeft("نَفَسٌ بَطِيءٌ وَعَمِيقٌ"))
    }

    func testArabicWithABrandNameAndNumbersStaysRightToLeft() {
        // Real scripts name products and quote figures in Latin and digits.
        XCTAssertTrue(ScriptDirection.isRightToLeft("أهلاً بكم في On Cue، لدينا ٣ نصائح و 12 دقيقة فقط اليوم للتدريب."))
    }

    func testLatinCyrillicAndGreekAreLeftToRight() {
        XCTAssertFalse(ScriptDirection.isRightToLeft("Hi everyone! Today I've got three simple tips."))
        XCTAssertFalse(ScriptDirection.isRightToLeft("Привет всем! Сегодня у меня три простых совета."))
        XCTAssertFalse(ScriptDirection.isRightToLeft("Γεια σας! Σήμερα έχω τρεις απλές συμβουλές."))
    }

    func testEnglishQuotingOneArabicWordStaysLeftToRight() {
        XCTAssertFalse(ScriptDirection.isRightToLeft("In Arabic you say مرحبا when you meet someone new at the studio."))
    }

    func testNoLettersIsLeftToRight() {
        XCTAssertFalse(ScriptDirection.isRightToLeft(""))
        XCTAssertFalse(ScriptDirection.isRightToLeft("   \n\n "))
        XCTAssertFalse(ScriptDirection.isRightToLeft("1, 2, 3 — 4!"))
    }
}
