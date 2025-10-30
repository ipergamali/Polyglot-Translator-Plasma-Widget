import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 1.15
import QtCore 6.5 as QtCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.kirigami 2.20 as Kirigami
import org.kde.plasma.plasmoid 2.0

PlasmoidItem {
    id: root
    width: 320
    height: 260
    implicitWidth: 320
    implicitHeight: 260
    Layout.minimumWidth: 320
    Layout.minimumHeight: 260
    Layout.maximumWidth: 440
    Layout.maximumHeight: 640

    readonly property var baseEngineOptions: [
        ({ label: "LibreTranslate", value: "translate_libre.py" }),
        ({ label: "Google Translate", value: "translate_google.py" }),
        ({ label: "MyMemory", value: "translate_mymemory.py" })
    ]

    property bool hasOfflineEngine: false
    property string selectedEngine: ""
    property string sourceLanguage: "auto"
    property string targetLanguage: "el"
    property bool isBusy: false
    property string statusMessage: ""
    property string currentJobToken: ""

    QtCore.Settings {
        id: settings
        category: "PolyglotTranslator"
        property string engine: ""
        property string sourceLang: "auto"
        property string targetLang: "el"
    }

    ListModel {
        id: engineModel
    }

    ListModel {
        id: sourceLanguageModel
        ListElement { label: "Auto Detect"; value: "auto" }
        ListElement { label: "English"; value: "en" }
        ListElement { label: "Spanish"; value: "es" }
        ListElement { label: "French"; value: "fr" }
        ListElement { label: "German"; value: "de" }
        ListElement { label: "Italian"; value: "it" }
        ListElement { label: "Portuguese"; value: "pt" }
        ListElement { label: "Russian"; value: "ru" }
        ListElement { label: "Chinese (Simplified)"; value: "zh" }
        ListElement { label: "Japanese"; value: "ja" }
        ListElement { label: "Korean"; value: "ko" }
        ListElement { label: "Greek"; value: "el" }
    }

    ListModel {
        id: targetLanguageModel
        ListElement { label: "English"; value: "en" }
        ListElement { label: "Spanish"; value: "es" }
        ListElement { label: "French"; value: "fr" }
        ListElement { label: "German"; value: "de" }
        ListElement { label: "Italian"; value: "it" }
        ListElement { label: "Portuguese"; value: "pt" }
        ListElement { label: "Russian"; value: "ru" }
        ListElement { label: "Chinese (Simplified)"; value: "zh" }
        ListElement { label: "Japanese"; value: "ja" }
        ListElement { label: "Korean"; value: "ko" }
        ListElement { label: "Greek"; value: "el" }
    }

    QtObject {
        id: clipboardHelper
        property var clipboard: null

        Component.onCompleted: {
            if (Qt.application && Qt.application.clipboard && Qt.application.clipboard.setText) {
                clipboard = Qt.application.clipboard;
            }
        }

        function setText(value) {
            if (clipboard) {
                if (clipboard.setText) {
                    clipboard.setText(value);
                } else {
                    clipboard.text = value;
                }
                return true;
            }
            if (Qt.application && Qt.application.clipboard && Qt.application.clipboard.setText) {
                Qt.application.clipboard.setText(value);
                return true;
            }
            if (executor) {
                executor.launch("qdbus", [
                    "org.kde.klipper",
                    "/klipper",
                    "org.kde.klipper.klipper.setClipboardContents",
                    value
                ], { type: "clipboard" });
                return true;
            }
            console.warn("No clipboard backend available for copy operation.");
            return false;
        }
    }

    Plasma5Support.DataSource {
        id: executor
        engine: "executable"
        property var activeJobs: ({})

        function launch(program, args, meta) {
            const command = buildCommand(program, args || []);
            activeJobs[command] = meta || {};
            activeJobs[command].program = program;
            activeJobs[command].args = args || [];
            activeJobs[command].stdout = "";
            activeJobs[command].stderr = "";
            connectSource(command);
            return command;
        }

        onNewData: function(sourceName, data) {
            const job = activeJobs[sourceName];
            if (!job) {
                disconnectSource(sourceName);
                return;
            }

            console.debug("Executor new data for", sourceName, JSON.stringify(data));

            const exitCode = data["exitCode"] !== undefined ? data["exitCode"] : data["exit code"];
            const exitStatus = data["exitStatus"] !== undefined ? data["exitStatus"] : data["exit status"];
            const isFinal =
                exitCode !== undefined ||
                exitStatus !== undefined ||
                data["error"] !== undefined ||
                data["errorString"] !== undefined;

            if (job.type === "translate") {
                if (data["stdout"]) {
                    job.stdout = (job.stdout || "") + data["stdout"];
                }
                if (data["stderr"]) {
                    job.stderr = (job.stderr || "") + data["stderr"];
                }

                if (!isFinal) {
                    return;
                }

                handleTranslationResult({
                    exitCode: exitCode,
                    exitStatus: exitStatus,
                    stdout: job.stdout,
                    stderr: job.stderr,
                    errorText: data["errorString"] || data["error"] || ""
                });
            } else if (job.type === "offlineCheck") {
                if (!isFinal) {
                    return;
                }
                const checkCode = exitCode !== undefined ? exitCode : exitStatus;
                hasOfflineEngine = checkCode === 0;
                if (hasOfflineEngine) {
                    appendOfflineEngineOption();
                } 
            } else if (job.type === "clipboard") {
                if (!isFinal) {
                    return;
                }
                const clipCode = exitCode !== undefined ? exitCode : exitStatus;
                if (clipCode !== 0) {
                    statusMessage = "Unable to copy to clipboard.";
                }
            }

            delete activeJobs[sourceName];
            disconnectSource(sourceName);
        }
    }

    function buildCommand(program, args) {
        const parts = [program].concat(args || []);
        return parts.map(shellQuote).join(" ");
    }

    function shellQuote(value) {
        const str = String(value !== undefined && value !== null ? value : "");
        if (str.length === 0) {
            return "''";
        }
        return "'" + str.replace(/'/g, "'\\''") + "'";
    }

    function handleTranslationResult(data) {
        isBusy = false;
        const trimmedStdout = data["stdout"] ? String(data["stdout"]).trim() : "";
        const trimmedStderr = data["stderr"] ? String(data["stderr"]).trim() : "";
        const exitCode = data["exitCode"];
        const exitStatus = data["exitStatus"];
        const hasExitCode = exitCode !== undefined && exitCode !== null && exitCode === exitCode;
        const normalizedExitCode = hasExitCode ? Number(exitCode) : undefined;
        const hasExitStatus = exitStatus !== undefined && exitStatus !== null;
        const normalizedStatus = hasExitStatus && typeof exitStatus === "string" ? exitStatus.toLowerCase() : exitStatus;
        const isSuccessfulExit =
            (hasExitCode && normalizedExitCode === 0) ||
            (!hasExitCode && hasExitStatus && (normalizedStatus === 0 || normalizedStatus === "0" || normalizedStatus === "normalexit"));

        if ((hasExitCode && normalizedExitCode === 0 && trimmedStdout.length > 0) ||
            (!hasExitCode && isSuccessfulExit && trimmedStdout.length > 0) ||
            (!hasExitCode && !hasExitStatus && trimmedStdout.length > 0)) {
            outputArea.text = trimmedStdout;
            statusMessage = "";
        } else if (trimmedStderr.length > 0) {
            statusMessage = trimmedStderr;
        } else if (data["errorText"] && data["errorText"].length > 0) {
            statusMessage = data["errorText"];
        } else {
            if (hasExitCode) {
                statusMessage = "Translation failed (exit code " + normalizedExitCode + ").";
            } else if (hasExitStatus) {
                statusMessage = "Translation failed (" + exitStatus + ").";
            } else {
                statusMessage = "Translation failed.";
            }
        }
    }

    function appendOfflineEngineOption() {
        for (let i = 0; i < engineModel.count; ++i) {
            if (engineModel.get(i).value === "offline") {
                return;
            }
        }
        engineModel.append({
            label: "Offline (translate-shell)",
            value: "offline"
        });
    }

    Component.onCompleted: {
        populateEngines();
        applyLegacyDefaults();
        restoreSelections();
        checkOfflineAvailability();
    }

    function populateEngines() {
        engineModel.clear();
        for (const engine of baseEngineOptions) {
            engineModel.append(engine);
        }
    }

    function restoreSelections() {
        selectedEngine = settings.engine && settings.engine.length > 0 ? settings.engine : engineModel.get(0).value;
        if (indexOfValue(engineModel, selectedEngine) === -1) {
            selectedEngine = engineModel.get(0).value;
        }
        sourceLanguage = settings.sourceLang && settings.sourceLang.length > 0 ? settings.sourceLang : "auto";
        if (indexOfValue(sourceLanguageModel, sourceLanguage) === -1) {
            sourceLanguage = "auto";
        }
        targetLanguage = settings.targetLang && settings.targetLang.length > 0 ? settings.targetLang : "el";
        if (indexOfValue(targetLanguageModel, targetLanguage) === -1) {
            targetLanguage = "el";
        }
    }

    function checkOfflineAvailability() {
        executor.launch("which", ["trans"], { type: "offlineCheck" });
    }

    function indexOfValue(model, value) {
        for (let i = 0; i < model.count; ++i) {
            if (model.get(i).value === value) {
                return i;
            }
        }
        return -1;
    }

    function safeIndex(model, value) {
        const idx = indexOfValue(model, value);
        return idx >= 0 ? idx : 0;
    }

    function toLocalFile(urlString) {
        if (!urlString) {
            return "";
        }

        const str = typeof urlString === "string" ? urlString : urlString.toString();
        if (str.startsWith("file://")) {
            return decodeURIComponent(str.substring(7));
        }
        return str;
    }

    function applyLegacyDefaults() {
        const needsEngine = !settings.engine || settings.engine.length === 0;
        const needsSource = !settings.sourceLang || settings.sourceLang.length === 0;
        const needsTarget = !settings.targetLang || settings.targetLang.length === 0;
        if (!needsEngine && !needsSource && !needsTarget) {
            return;
        }

        const legacy = readLegacyIniDefaults();
        if (!legacy) {
            return;
        }

        if (needsEngine && legacy.engine) {
            settings.engine = legacy.engine;
        }
        if (needsSource && legacy.sourceLang) {
            settings.sourceLang = legacy.sourceLang;
        }
        if (needsTarget && legacy.targetLang) {
            settings.targetLang = legacy.targetLang;
        }
        settings.sync();
    }

    function readLegacyIniDefaults() {
        const url = Qt.resolvedUrl("../../PolyglotTranslator.ini");
        const request = new XMLHttpRequest();
        try {
            request.open("GET", url, false);
            request.send();
        } catch (error) {
            console.debug("Unable to read legacy settings file:", error);
            return null;
        }

        if (request.status !== 0 && (request.status < 200 || request.status >= 300)) {
            return null;
        }

        return parseIniSection(request.responseText || "");
    }

    function parseIniSection(text) {
        const result = {};
        let inSection = false;
        const lines = text.split(/\r?\n/);
        for (let i = 0; i < lines.length; ++i) {
            const trimmed = lines[i].trim();
            if (trimmed.length === 0 || trimmed.startsWith(";") || trimmed.startsWith("#")) {
                continue;
            }
            if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
                inSection = trimmed.substring(1, trimmed.length - 1) === "PolyglotTranslator";
                continue;
            }
            if (!inSection) {
                continue;
            }
            const equalsIndex = trimmed.indexOf("=");
            if (equalsIndex === -1) {
                continue;
            }
            const key = trimmed.substring(0, equalsIndex).trim();
            const value = trimmed.substring(equalsIndex + 1).trim();
            if (key.length === 0) {
                continue;
            }
            result[key] = value;
        }
        return result;
    }

    function translate() {
        if (isBusy) {
            return;
        }

        const input = inputArea.text.trim();
        if (input.length === 0) {
            statusMessage = "Please enter text to translate.";
            return;
        }

        const engineIndex = indexOfValue(engineModel, selectedEngine);
        if (engineIndex < 0) {
            statusMessage = "Invalid engine selection.";
            return;
        }

        const engine = engineModel.get(engineIndex);
        statusMessage = "";
        isBusy = true;

        if (engine.value === "offline") {
            runOfflineTranslation(input);
            return;
        }

        const scriptUrl = Qt.resolvedUrl("../scripts/" + engine.value);
        const scriptPath = toLocalFile(scriptUrl);
        const args = [scriptPath, input, targetLanguage];
        if (sourceLanguage && sourceLanguage !== "auto") {
            args.push(sourceLanguage);
        }

        console.debug("Launching translation", JSON.stringify(args));
        currentJobToken = executor.launch("python3", args, {
            type: "translate",
            program: "python3",
            args: args
        });
    }

    function runOfflineTranslation(text) {
        if (!hasOfflineEngine) {
            statusMessage = "translate-shell is not available on this system.";
            isBusy = false;
            return;
        }

        const args = ["-no-auto", "-brief", ":" + (sourceLanguage || "auto") + ":" + targetLanguage, text];
        currentJobToken = executor.launch("trans", args, { type: "translate" });
    }

    function copyResultToClipboard() {
        if (!outputArea.text || outputArea.text.length === 0) {
            return;
        }

        if (!clipboardHelper.setText(outputArea.text)) {
            statusMessage = "Unable to copy to clipboard.";
        }
    }

    function persistSelections() {
        settings.engine = selectedEngine;
        settings.sourceLang = sourceLanguage;
        settings.targetLang = targetLanguage;
        settings.sync();
    }

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: 12
        radius: 12
        Kirigami.Theme.colorSet: Kirigami.Theme.View
        Kirigami.Theme.inherit: false
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.disabledTextColor
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Label {
                text: "Polyglot Translator"
                font.family: "Noto Sans"
                font.pointSize: 14
                font.weight: Font.Medium
                color: Kirigami.Theme.textColor
            }

            TextArea {
                id: inputArea
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                placeholderText: "Type or paste text to translate…"
                wrapMode: TextArea.Wrap
                font.family: "Noto Sans"
                font.pointSize: 14
                color: Kirigami.Theme.textColor
                Component.onCompleted: {
                    const len = text.length;
                    if (cursorPosition > len) {
                        cursorPosition = len;
                    }
                }
                onTextChanged: {
                    const len = text.length;
                    if (cursorPosition > len) {
                        cursorPosition = len;
                    }
                }
                background: Rectangle {
                    radius: 8
                    color: Qt.lighter(Kirigami.Theme.backgroundColor, 1.1)
                    border.color: Kirigami.Theme.disabledTextColor
                }
                onEditingFinished: translate()
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ComboBox {
                    id: engineCombo
                    Layout.fillWidth: true
                    model: engineModel
                    textRole: "label"
                    valueRole: "value"
                    font.family: "Noto Sans"
                    font.pointSize: 13
                    currentIndex: safeIndex(engineModel, selectedEngine)
                    onActivated: function(index) {
                        selectedEngine = engineModel.get(index).value;
                        persistSelections();
                    }
                }

                BusyIndicator {
                    running: isBusy
                    visible: running
                    width: 22
                    height: 22
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ComboBox {
                    id: sourceCombo
                    Layout.fillWidth: true
                    model: sourceLanguageModel
                    textRole: "label"
                    valueRole: "value"
                    font.family: "Noto Sans"
                    font.pointSize: 13
                    currentIndex: safeIndex(sourceLanguageModel, sourceLanguage)
                    onActivated: function(index) {
                        sourceLanguage = sourceLanguageModel.get(index).value;
                        persistSelections();
                    }
                }

                ComboBox {
                    id: targetCombo
                    Layout.fillWidth: true
                    model: targetLanguageModel
                    textRole: "label"
                    valueRole: "value"
                    font.family: "Noto Sans"
                    font.pointSize: 13
                    currentIndex: safeIndex(targetLanguageModel, targetLanguage)
                    onActivated: function(index) {
                        targetLanguage = targetLanguageModel.get(index).value;
                        persistSelections();
                    }
                }
            }

            PlasmaComponents3.Button {
                id: translateButton
                Layout.fillWidth: true
                text: isBusy ? "Translating…" : "Translate"
                enabled: !isBusy
                font.family: "Noto Sans"
                font.pointSize: 13
                onClicked: translate()
                background: Rectangle {
                    radius: 8
                    color: Kirigami.Theme.highlightColor
                }
                contentItem: Label {
                    text: translateButton.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: Kirigami.Theme.highlightedTextColor
                    font: translateButton.font
                }
            }

            TextArea {
                id: outputArea
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                readOnly: true
                wrapMode: TextArea.Wrap
                font.family: "Noto Sans"
                font.pointSize: 14
                color: Kirigami.Theme.textColor
                placeholderText: "Translation will appear here."
                Component.onCompleted: {
                    const len = text.length;
                    if (cursorPosition > len) {
                        cursorPosition = len;
                    }
                }
                onTextChanged: {
                    const len = text.length;
                    if (cursorPosition > len) {
                        cursorPosition = len;
                    }
                }
                background: Rectangle {
                    radius: 8
                    color: Qt.lighter(Kirigami.Theme.backgroundColor, 1.08)
                    border.color: Kirigami.Theme.disabledTextColor
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Item {
                    Layout.fillWidth: true
                }

                PlasmaComponents3.Button {
                    text: "Copy Result"
                    enabled: outputArea.text.length > 0
                    font.family: "Noto Sans"
                    font.pointSize: 12
                    onClicked: copyResultToClipboard()
                }
            }

            Label {
                Layout.fillWidth: true
                visible: statusMessage.length > 0
                text: statusMessage
                wrapMode: Text.Wrap
                color: Kirigami.Theme.negativeTextColor
                font.family: "Noto Sans"
                font.pointSize: 11
            }
        }
    }
}
