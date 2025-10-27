import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 1.15
import Qt.labs.settings 1.1
import Qt.labs.platform 1.1 as Platform
import org.kde.plasma.core 6.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3
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
        ({ label: "DeepL", value: "translate_deepl.py" }),
        ({ label: "MyMemory", value: "translate_mymemory.py" })
    ]

    property bool hasOfflineEngine: false
    property string selectedEngine: ""
    property string sourceLanguage: "auto"
    property string targetLanguage: "en"
    property bool isBusy: false
    property string statusMessage: ""
    property string currentJobToken: ""

    Settings {
        id: settings
        category: "PolyglotTranslator"
        fileName: "PolyglotTranslator.ini"
        property string engine: ""
        property string sourceLang: "auto"
        property string targetLang: "en"
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
    }

    Platform.Clipboard {
        id: clipboard
    }

    PlasmaCore.DataSource {
        id: executor
        engine: "executable"
        property var activeJobs: ({})

        function launch(program, args, meta) {
            const token = program + ":" + Date.now() + ":" + Math.random().toString(16).slice(2);
            activeJobs[token] = meta || {};
            activeJobs[token].program = program;
            activeJobs[token].args = args;
            connectSource(token, { "cmd": program, "arguments": args });
            return token;
        }

        onNewData: function(sourceName, data) {
            const job = activeJobs[sourceName];
            if (!job) {
                disconnectSource(sourceName);
                return;
            }

            if (job.type === "translate") {
                handleTranslationResult(data);
            } else if (job.type === "offlineCheck") {
                hasOfflineEngine = data["exitCode"] === 0;
                if (hasOfflineEngine) {
                    appendOfflineEngineOption();
                }
            }

            delete activeJobs[sourceName];
            disconnectSource(sourceName);
        }
    }

    function handleTranslationResult(data) {
        isBusy = false;
        const trimmedStdout = data["stdout"] ? data["stdout"].trim() : "";
        const trimmedStderr = data["stderr"] ? data["stderr"].trim() : "";

        if (data["exitCode"] === 0 && trimmedStdout.length > 0) {
            outputArea.text = trimmedStdout;
            statusMessage = "";
        } else if (trimmedStderr.length > 0) {
            statusMessage = trimmedStderr;
        } else {
            statusMessage = "Translation failed (exit code " + data["exitCode"] + ").";
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
        targetLanguage = settings.targetLang && settings.targetLang.length > 0 ? settings.targetLang : "en";
        if (indexOfValue(targetLanguageModel, targetLanguage) === -1) {
            targetLanguage = "en";
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

    function toLocalFile(urlString) {
        if (!urlString) {
            return "";
        }

        if (urlString.startsWith("file://")) {
            return decodeURIComponent(urlString.substring(7));
        }
        return urlString;
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

        currentJobToken = executor.launch("python3", args, { type: "translate" });
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

    function persistSelections() {
        settings.engine = selectedEngine;
        settings.sourceLang = sourceLanguage;
        settings.targetLang = targetLanguage;
        settings.sync();
    }

    PlasmaCore.ColorScope {
        anchors.fill: parent
        colorGroup: PlasmaCore.Theme.View

        Rectangle {
            id: card
            anchors.fill: parent
            anchors.margins: 12
            radius: 12
            color: PlasmaCore.Theme.backgroundColor
            border.color: PlasmaCore.Theme.disabledTextColor
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
                    color: PlasmaCore.Theme.textColor
                }

                TextArea {
                    id: inputArea
                    Layout.fillWidth: true
                    Layout.preferredHeight: 80
                    placeholderText: "Type or paste text to translate…"
                    wrapMode: TextArea.Wrap
                    font.family: "Noto Sans"
                    font.pointSize: 14
                    color: PlasmaCore.Theme.textColor
                    background: Rectangle {
                        radius: 8
                        color: PlasmaCore.Theme.backgroundColor.lighter(110)
                        border.color: PlasmaCore.Theme.disabledTextColor
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
                        currentIndex: {
                            const idx = indexOfValue(engineModel, selectedEngine);
                            return idx >= 0 ? idx : 0;
                        }
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
                        currentIndex: {
                            const idx = indexOfValue(sourceLanguageModel, sourceLanguage);
                            return idx >= 0 ? idx : 0;
                        }
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
                        currentIndex: {
                            const idx = indexOfValue(targetLanguageModel, targetLanguage);
                            return idx >= 0 ? idx : 0;
                        }
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
                        color: PlasmaCore.Theme.highlightColor
                    }
                    contentItem: Label {
                        text: translateButton.text
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: PlasmaCore.Theme.highlightedTextColor
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
                    color: PlasmaCore.Theme.textColor
                    placeholderText: "Translation will appear here."
                    background: Rectangle {
                        radius: 8
                        color: PlasmaCore.Theme.backgroundColor.lighter(108)
                        border.color: PlasmaCore.Theme.disabledTextColor
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
                        onClicked: clipboard.text = outputArea.text
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: statusMessage.length > 0
                    text: statusMessage
                    wrapMode: Text.Wrap
                    color: PlasmaCore.Theme.negativeTextColor
                    font.family: "Noto Sans"
                    font.pointSize: 11
                }
            }
        }
    }
}
