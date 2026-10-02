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
            let appleLocale = ["pt-BR": "pt_BR", "it": "it_IT", "es-MX": "es_MX", "ru": "ru_RU", "uk": "uk_UA", "ar": "ar_SA", "en-US": "en_US"][locale] ?? locale
            app.launchArguments += ["-AppleLanguages", "(\(locale))", "-AppleLocale", appleLocale]
            app.launchEnvironment["UITEST_SCRIPT"] = script
        }
        app.launch()
    }

    private static let scripts: [String: String] = [
        "en-US": """
        Hi everyone! Today I've got three simple tips for anyone who's nervous about speaking in public.

        The first is to breathe before you start. It sounds obvious, but almost nobody does it. One slow, deep breath calms your voice and gives you time to line up your first sentence.

        The second tip is to speak more slowly than you think you need to. When we're nervous, we speed up without noticing. Your listeners need time to follow the idea, and a pause in the right place is worth more than any clever word.

        The third is to look at people, not at the floor. Pick a friendly face in the audience and talk to them like it's a conversation. Then pick another. Within a few minutes, the whole room will feel you're talking to each of them.

        You don't have to be perfect. Nobody remembers a small mistake; people remember how you made them feel.

        If these tips helped, tell me in the comments which one you'll try first. See you next time!
        """,
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
        "es-MX": """
        ¡Hola a todos! Hoy les traigo tres consejos sencillos para quienes tienen miedo de hablar en público.

        El primero es respirar antes de empezar. Parece obvio, pero casi nadie lo hace. Una respiración lenta y profunda calma la voz y te da tiempo para ordenar la primera frase.

        El segundo consejo es hablar más despacio de lo que crees necesario. Cuando estamos nerviosos, aceleramos sin darnos cuenta. Quien escucha necesita tiempo para seguir la idea, y una pausa en el momento justo vale más que cualquier palabra difícil.

        El tercero es mirar a las personas, no al suelo. Elige una cara amable entre el público y háblale como en una conversación. Después, elige otra. En pocos minutos, toda la sala sentirá que le hablas a cada uno.

        No hace falta ser perfecto. Nadie recuerda un pequeño error; la gente recuerda cómo la hiciste sentir.

        Si estos consejos te sirvieron, cuéntame en los comentarios cuál vas a probar primero. ¡Hasta la próxima!
        """,
        "ru": """
        Привет всем! Сегодня у меня три простых совета для тех, кто боится выступать на публике.

        Первый — сделайте вдох перед началом. Кажется очевидным, но почти никто так не делает. Медленный глубокий вдох успокаивает голос и даёт время собраться с первой фразой.

        Второй совет — говорите медленнее, чем вам кажется нужным. Когда мы волнуемся, мы ускоряемся, сами того не замечая. Слушателям нужно время, чтобы уловить мысль, и пауза в нужном месте стоит больше любого сложного слова.

        Третий — смотрите на людей, а не в пол. Найдите в зале дружелюбное лицо и говорите с ним, как в обычном разговоре. Потом выберите другое. Через несколько минут весь зал почувствует, что вы обращаетесь к каждому.

        Не нужно быть идеальным. Никто не помнит маленькую ошибку; люди помнят, что они почувствовали.

        Если советы помогли, напишите в комментариях, какой попробуете первым. До встречи!
        """,
        "uk": """
        Привіт усім! Сьогодні в мене три прості поради для тих, хто боїться виступати на публіці.

        Перша — зробіть вдих перед початком. Здається очевидним, але майже ніхто так не робить. Повільний глибокий вдих заспокоює голос і дає час зібратися з першою фразою.

        Друга порада — говоріть повільніше, ніж вам здається потрібним. Коли ми хвилюємося, ми пришвидшуємося, самі того не помічаючи. Слухачам потрібен час, щоб вловити думку, і пауза в потрібному місці варта більше за будь-яке складне слово.

        Третя — дивіться на людей, а не в підлогу. Знайдіть у залі привітне обличчя і говоріть із ним, як у звичайній розмові. Потім оберіть інше. За кілька хвилин уся зала відчує, що ви звертаєтеся до кожного.

        Не треба бути ідеальним. Ніхто не пам'ятає маленької помилки; люди пам'ятають, що вони відчули.

        Якщо поради допомогли, напишіть у коментарях, яку спробуєте першою. До зустрічі!
        """,
        "ar": """
        مرحباً بالجميع! اليوم أقدّم لكم ثلاث نصائح بسيطة لمن يخاف من التحدث أمام الجمهور.

        النصيحة الأولى هي أن تتنفس قبل أن تبدأ. يبدو هذا بديهياً، لكن لا أحد تقريباً يفعله. نفَس بطيء وعميق يهدّئ الصوت ويمنحك وقتاً لترتيب جملتك الأولى.

        النصيحة الثانية هي أن تتكلم أبطأ مما تظن أنه ضروري. عندما نتوتر، نُسرع دون أن ننتبه. من يستمع إليك يحتاج إلى وقت ليتابع الفكرة، ووقفة في المكان المناسب أثمن من أي كلمة صعبة.

        النصيحة الثالثة هي أن تنظر إلى الناس، لا إلى الأرض. اختر وجهاً ودوداً بين الحضور وتحدّث إليه كأنها محادثة عادية. ثم اختر وجهاً آخر. خلال دقائق قليلة، ستشعر القاعة كلها أنك تخاطب كل واحد فيها.

        لا داعي لأن تكون مثالياً. لا أحد يتذكر خطأً صغيراً؛ الناس يتذكرون كيف جعلتهم يشعرون.

        إذا أفادتك هذه النصائح، اكتب في التعليقات أيّها ستجرّب أولاً. إلى اللقاء!
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
