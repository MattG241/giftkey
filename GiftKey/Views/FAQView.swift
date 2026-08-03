//
//  FAQView.swift
//  GiftKey
//
//  Short, plain-language answers. The Full Access question is the one that decides
//  whether a cautious IT manager lets staff install this, so it goes first and answers
//  honestly.
//

import SwiftUI

struct FAQView: View {

    private struct Entry: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
    }

    private let entries: [Entry] = [
        Entry(
            question: "Why does GiftKey need Full Access?",
            answer: """
            Two reasons, both mechanical:

            1. Camera. iOS blocks a keyboard extension from opening the camera unless \
            Full Access is on. No Full Access, no scanning.

            2. Settings. Your validation filter, prefix, symbology choices and so on live \
            in a shared container. A keyboard without Full Access cannot read that \
            container, so it would have no idea what you configured.

            Full Access is a broad permission, and it is fair to be suspicious of any \
            keyboard that asks for it. The honest answer is below.
            """
        ),
        Entry(
            question: "What does GiftKey do with what I type?",
            answer: """
            Nothing. GiftKey never reads the contents of the field you are editing. It \
            only writes into it.

            There is no analytics code, no crash reporting SDK, no advertising SDK, and \
            no networking code of any kind in either the app or the keyboard. Not \
            disabled - absent. The App Store privacy label is "Data Not Collected".
            """
        ),
        Entry(
            question: "Are scans saved anywhere?",
            answer: """
            No. A scanned code lives in memory just long enough to be typed.

            The one exception is "Scan in app" mode, where the code is passed from the \
            app to the keyboard through a shared container on your device. That handoff \
            is deleted the moment the keyboard uses it, and expires by itself after 60 \
            seconds.
            """
        ),
        Entry(
            question: "Does the camera image go anywhere?",
            answer: """
            No. Barcode decoding runs entirely on the device, using Apple's own \
            frameworks. Camera frames are never written to disk, never saved to your \
            photo library, and never uploaded.
            """
        ),
        Entry(
            question: "The keyboard says a code was rejected. Why?",
            answer: """
            A validation filter is on and the scanned code did not match it.

            The built-in "Gift card (8-20 digits)" filter only accepts 8 to 20 digits. \
            That is deliberate: it stops a product barcode or a QR code being typed into \
            a gift card field. Change or turn off the filter in Settings > Validation \
            filter.
            """
        ),
        Entry(
            question: "In keyboard or in app - which should I use?",
            answer: """
            "In keyboard" is faster: you never leave the POS app. Use it if it feels \
            smooth on your iPhone.

            "In app" opens GiftKey, scans full screen, then hands the code back. It is \
            better on older iPhones where the small in-keyboard preview is sluggish, and \
            it is the automatic fallback if the in-keyboard camera cannot start.
            """
        ),
        Entry(
            question: "Is it really free?",
            answer: """
            Yes. No purchase, no subscription, no scan limits, no ads, no account.
            """
        ),
        Entry(
            question: "Nothing happens when I tap Scan.",
            answer: """
            Check, in order:

            1. Full Access is on for GiftKey.
            2. Camera access is allowed in Settings > GiftKey > Camera.
            3. The barcode type you are scanning is enabled in Settings > Barcode types.

            If the keyboard reports that the camera could not start, switch Scan mode to \
            "In app" - some older devices cannot run a capture session inside a keyboard.
            """
        ),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No scan data is stored or transmitted.")
                                .font(.headline)
                            Text("Neither target contains networking code.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                    }
                }

                ForEach(entries) { entry in
                    Section(entry.question) {
                        Text(entry.answer)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("FAQ")
        }
    }
}
