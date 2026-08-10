import PostHogSupportChatClient
import SwiftUI

/// "Before we start..." form shown once, before the first-ever message, when
/// the project config has `requireEmail` enabled. The email labels tickets in
/// the PostHog inbox, powers email reply notifications, and acts as the
/// recovery key for reinstalls.
struct IdentificationFormView: View {
    let client: SupportChatClient
    @State private var email = ""
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    private var isEmailValid: Bool {
        email.contains("@") && email.contains(".") && email.count >= 5
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Email", bundle: .module,
                                     comment: "Email text field label in the support contact form."),
                              text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if client.remoteConfig?.collectName == true {
                        TextField(String(localized: "Name", bundle: .module,
                                         comment: "Name text field label in the support contact form."),
                                  text: $name)
                            .textContentType(.name)
                    }
                } header: {
                    client.remoteConfig?.identificationFormTitle.map(Text.init)
                        ?? Text("Before we start...", bundle: .module,
                                // swiftlint:disable:next line_length
                                comment: "Header of the form asking for the user's email before the first support message. Fallback when the project config does not provide one.")
                } footer: {
                    client.remoteConfig?.identificationFormDescription.map(Text.init)
                        ?? Text("We use your email to follow up on your request.", bundle: .module,
                                comment: "Footer of the email form explaining why the email is needed. Fallback when the project config does not provide one.")
                }

                Button {
                    client.setIdentification(email: email.trimmingCharacters(in: .whitespaces),
                                             name: name.isEmpty ? nil : name)
                    dismiss()
                } label: {
                    Text("Continue", bundle: .module, comment: "Submit button of the support contact form.")
                }
                .disabled(!isEmailValid)
            }
            .navigationTitle(Text("Support", bundle: .module,
                                  comment: "Navigation title of the support chat screen. Keep it short."))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
