import XCTest

/// Raw material for App Store marketing screenshots — real screens, no
/// mockups. Headline text is composited on afterward; this only captures
/// the app states that make the case for each headline.
final class MarketingCaptures: XCTestCase {

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Localized storefront sets. Run with `TEST_RUNNER_MARKETING_LOCALE=pt-BR`
    /// (or `it`) to put the device in that language and load a script written
    /// in it; unset, the English set is captured as before.
    private func stage(_ app: XCUIApplication) {
        let locale = ProcessInfo.processInfo.environment["MARKETING_LOCALE"] ?? ""
        if let script = Self.scripts[locale] {
            let appleLocale = ["pt-BR": "pt_BR", "it": "it_IT"][locale] ?? locale
            app.launchArguments += ["-AppleLanguages", "(\(locale))", "-AppleLocale", appleLocale]
            app.launchEnvironment["UITEST_SCRIPT"] = script
        }
        app.launch()
    }

    private static let scripts: [String: String] = [
        "pt-BR": """
        Oi, pessoal! Hoje eu trouxe três dicas simples para quem tem medo de falar em público.

        A primeira é respirar antes de começar. Parece óbvio, mas quase ninguém faz. Uma respiração lenta e profunda acalma a voz e dá tempo para organizar a primeira frase.

        A segunda dica é falar mais devagar do que você acha que precisa. Quando estamos nervosos, a gente acelera sem perceber. Quem está ouvindo precisa de tempo para acompanhar a ideia, e uma pausa no lugar certo vale mais do que qualquer palavra difícil.

        A terceira é olhar para as pessoas, não para o chão. Escolha um rosto amigo na plateia e fale com ele como se fosse uma conversa. Depois, escolha outro. Em poucos minutos, a sala inteira vai sentir que você está falando com cada um.

        Não precisa ser perfeito. Ninguém lembra de um erro pequeno; as pessoas lembram de como você as fez sentir.

        Se essas dicas te ajudaram, conta nos comentários qual delas você vai testar primeiro. Até a próxima!
        """,
        "it": """
        Ciao a tutti! Oggi vi porto tre consigli semplici per chi ha paura di parlare in pubblico.

        Il primo è respirare prima di cominciare. Sembra ovvio, ma quasi nessuno lo fa. Un respiro lento e profondo calma la voce e vi dà il tempo di organizzare la prima frase.

        Il secondo consiglio è parlare più piano di quanto pensiate. Quando siamo nervosi, acceleriamo senza accorgercene. Chi ascolta ha bisogno di tempo per seguire l'idea, e una pausa al momento giusto vale più di qualsiasi parola difficile.

        Il terzo è guardare le persone, non il pavimento. Scegliete un volto amico tra il pubblico e parlategli come in una conversazione. Poi sceglietene un altro. In pochi minuti, tutta la sala sentirà che state parlando proprio a ciascuno.

        Non serve essere perfetti. Nessuno ricorda un piccolo errore; le persone ricordano come le avete fatte sentire.

        Se questi consigli vi sono stati utili, scrivete nei commenti quale proverete per primo. Alla prossima!
        """,
    ]

    /// It listens: cursor placed mid-script so spoken / active / upcoming
    /// word states are all visible, as if mid-take.
    func testListening() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingNoCamera", "-uiTestingCursorAt", "18"]
        stage(app)
        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))
        attach(XCUIScreen.main.screenshot(), named: "m-listening")
    }

    /// Mirrors for a teleprompter rig.
    func testMirroring() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingNoCamera", "-uiTestingCursorAt", "58", "-uiTestingMirrorOn"]
        stage(app)
        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 5))
        attach(XCUIScreen.main.screenshot(), named: "m-mirroring")
    }

    /// The pre-roll leader.
    func testLeader() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingNoCamera", "-uiTestingCursorAt", "18", "-uiTestingShowCountdown"]
        stage(app)
        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Restart"].waitForExistence(timeout: 5))
        attach(XCUIScreen.main.screenshot(), named: "m-leader")
    }

    /// Records straight from the phone, camera badge and all.
    func testRecording() throws {
        let app = XCUIApplication()
        // A different point in the script from the listening shot: two frames
        // of the same paragraph read as a duplicate in the App Store set.
        app.launchArguments = ["-uiTestingNoCamera", "-uiTestingCursorAt", "96", "-uiTestingShowRecording"]
        stage(app)
        app.buttons["Start prompting →"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))
        attach(XCUIScreen.main.screenshot(), named: "m-recording")
    }

    /// Write or open a script — the editor, full-screen and empty of chrome.
    func testEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingNoCamera"]
        stage(app)
        XCTAssertTrue(app.buttons["Start prompting →"].waitForExistence(timeout: 5))
        attach(XCUIScreen.main.screenshot(), named: "m-editor")
    }
}
