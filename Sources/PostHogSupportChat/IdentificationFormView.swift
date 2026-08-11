import PostHogSupportChatClient
import SwiftUI

/// Optional email ask shown once per session before the first message, when
/// the project config has `requireEmail` enabled. The email lets the team
/// reply by mail, labels tickets in the PostHog inbox, and acts as the
/// recovery key for reinstalls — but the user can decline and chat anyway.
struct IdentificationFormView: View {
    let client: SupportChatClient
    var strings: SupportChatStrings = .init()
    @State private var email = ""
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    private var title: Text {
        let fallback = LocalizedStringResource("Before we start...",
                                               bundle: .package,
                                               comment: "Header of the form asking for the user's email before the first support message.")
        return SupportChatStrings.text(strings.identificationTitle,
                                       dashboard: client.remoteConfig?.identificationFormTitle,
                                       fallback: fallback)
    }

    private var explanation: Text {
        let fallback = LocalizedStringResource("Add your email so we can get back to you.",
                                               bundle: .package,
                                               comment: "Description of the optional email form, explaining the email is used to reply to the user.")
        return SupportChatStrings.text(strings.identificationDescription,
                                       dashboard: client.remoteConfig?.identificationFormDescription,
                                       fallback: fallback)
    }

    private var isEmailValid: Bool {
        email.contains("@") && email.contains(".") && email.count >= 5
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            title
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            explanation
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField(String(localized: "Email", bundle: .module,
                             comment: "Email text field label in the support contact form."),
                      text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if client.remoteConfig?.collectName == true {
                TextField(String(localized: "Name", bundle: .module,
                                 comment: "Name text field label in the support contact form."),
                          text: $name)
                    .textContentType(.name)
                    .padding(12)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                client.setIdentification(email: email.trimmingCharacters(in: .whitespaces),
                                         name: name.isEmpty ? nil : name)
                dismiss()
            } label: {
                Text("Continue", bundle: .module, comment: "Submit button of the support contact form.")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    // SwiftUI's disabled borderedProminent desaturates to a
                    // murky gray in dark mode; the widget convention is to
                    // keep the accent and dim it instead.
                    .background(.tint.opacity(isEmailValid ? 1 : 0.45), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!isEmailValid)
            .padding(.top, 6)

            Button {
                client.identificationDeclined = true
                dismiss()
            } label: {
                Text("Not now", bundle: .module,
                     comment: "Button that skips the optional email form and continues to the chat.")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}
