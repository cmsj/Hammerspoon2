//
//  ChooserRowView.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 11/06/2026.
//

import Foundation
import SwiftUI

struct ChooserRowView: View {
    let item: ChooserItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subText = item.subText {
                    Text(subText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(height: ChooserViewModel.rowHeight)
        .padding(.horizontal, 16)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.18)
                : Color.clear,
            in: Rectangle()
        )
        .opacity(item.isValid ? 1.0 : 0.4)
    }
}
