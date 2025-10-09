//
//  AboutView.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 09/10/2025.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    private var glowColor = Color(red: 0.984, green: 0.537, blue: 0.122, opacity: 0.6) // FB891F

    private let appInfo = HSAppInfo()

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(colorScheme == .dark ? .black.opacity(0.3) : .white)
                    .allowsHitTesting(false)
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Image(systemName: "hammer") // FIXME: Proper logo here
                            .resizable()
                            .frame(width: 103, height: 103, alignment: .center)
                            .clipShape(.buttonBorder)
                            .shadow(color: colorScheme == .dark ? glowColor : .clear, radius: 50)
                            .padding([.top], 30)
                            .allowsHitTesting(false)
                        Text("Hammerspoon 2")
                            .font(.system(size: 32))
                            .fontWeight(.bold)
                            .padding([.top], 14)
                            .allowsHitTesting(false)
                        Text("Version \(appInfo.version) (\(appInfo.build))")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                        Text(appInfo.copyrightNotice)
                            .padding([.top, .bottom])
                            .allowsHitTesting(false)

                        Divider()
                            .padding([.leading, .trailing, .bottom])
                            .allowsHitTesting(false)

                        HStack {
                            Spacer()
                            Text("Icon by Juerd Waalboer")
                                .font(.system(size: 14))
                            Spacer()
                        }

                        Divider()
                            .padding()
                            .allowsHitTesting(false)

                        Text("Hammerspoon is proudly Open Source and is the work of many dedicated volunteers.")
                            .multilineTextAlignment(.center)
                            .padding([.leading, .trailing], 30)
                            .allowsHitTesting(false)

                        Divider()
                            .padding()
                            .allowsHitTesting(false)
                    }
                    //                    .border(.green)
                }
            }
            //            .border(.red)
        }
        .ignoresSafeArea()
        .frame(width: 400, height: 400)
    }
}

#Preview {
    AboutView()
}
