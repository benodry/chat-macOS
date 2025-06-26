//
//  MessageView.swift
//  HuggingChat-Mac
//
//  Created by Cyril Zakka on 12/13/24.
//

import SwiftUI
import MarkdownView

struct MessageView: View {
    
    @AppStorage("inlineCodeHiglight") private var inlineCodeHiglight: AccentColorOption = .blue
    @AppStorage("lightCodeBlockTheme") private var lightCodeBlockTheme: String = "xcode"
    @AppStorage("darkCodeBlockTheme") private var darkCodeBlockTheme: String = "monokai-sublime"
    
    let message: MessageRow
    
    var body: some View {
        ZStack(alignment: message.type == .user ? .trailing:.leading) {
            MarkdownView(message.content)
                .padding(.horizontal, message.type == .user ? 10:0)
                .padding(.vertical, 8)
                .background(message.type == .user ? RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.gray.opacity(0.3)):nil)
        }
        .frame(maxWidth: .infinity, alignment: message.type == .user ? .trailing:.leading)
        .onChange(of: message.content) {
            print(message.content)
        }
    }
}

#Preview("dark") {
    ChatView()
        .frame(width: 300, height: 500)
        .environment(ModelManager())
        .environment(ConversationViewModel())
        .environment(AudioModelManager())
        .environment(MenuViewModel())
        .colorScheme(.dark)
}
