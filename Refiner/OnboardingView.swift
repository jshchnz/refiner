//
//  OnboardingView.swift
//  Refiner
//

import SwiftUI

struct OnboardingView: View {
    var onDismiss: () -> Void

    @State private var visibleRows: Int = 0
    @State private var showButton = false

    private let features: [(icon: String, title: String, subtitle: String)] = [
        ("clipboard", "Paste anything", "JSON, XML, CSV, Markdown, code, and more"),
        ("sparkle.magnifyingglass", "Auto-detect & format", "Interactive trees, syntax highlighting, and tables"),
        ("command", "Summon from anywhere", "Cmd+Opt+R from any app (customizable)"),
        ("macwindow.on.rectangle", "Always on top", "Floats across all spaces"),
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            VStack(spacing: 6) {
                Text("Welcome to Refiner")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Instant formatting for your clipboard")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 2) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    HStack(spacing: 12) {
                        Image(systemName: feature.icon)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                                .fontWeight(.medium)
                            Text(feature.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.06))
                    )
                    .opacity(index < visibleRows ? 1 : 0)
                    .offset(y: index < visibleRows ? 0 : 10)
                    .animation(.easeOut(duration: 0.35).delay(Double(index) * 0.1), value: visibleRows)
                }
            }
            .padding(.horizontal, 24)

            Button {
                onDismiss()
            } label: {
                Text("Get Started")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Capsule())
            .opacity(showButton ? 1 : 0)
            .scaleEffect(showButton ? 1 : 0.8)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showButton)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onAppear {
            visibleRows = features.count
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showButton = true
            }
        }
    }
}
