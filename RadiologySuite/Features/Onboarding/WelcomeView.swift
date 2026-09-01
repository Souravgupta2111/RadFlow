import SwiftUI

struct WelcomeView: View {
    @AppStorage("welcome.complete") var welcomeComplete = false

    var body: some View {
        ZStack {
            // Dark Background
            Color.black.ignoresSafeArea()
            
            // Vibrant Radial Gradient Blob
            GeometryReader { proxy in
                RadialGradient(
                    gradient: Gradient(colors: [
                        DS.coral.opacity(0.8),
                        DS.coral.opacity(0.4),
                        Color.clear
                    ]),
                    center: .top,
                    startRadius: 0,
                    endRadius: proxy.size.width * 1.1
                )
                .ignoresSafeArea()
                .offset(y: -proxy.size.height * 0.1)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                
                // Brand
                HStack(spacing: 8) {
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 20, weight: .bold))
                    Text("Radflow")
                        .font(.system(size: 22, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.bottom, 16)
                
                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text("Speak Medical with")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Precision")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(DS.coral)
                }
                .padding(.bottom, 16)
                
                // Subtitle
                Text("Dictate your findings naturally, generate structured templates, and save hours of documentation time - effortlessly.")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineSpacing(4)
                    .padding(.bottom, 40)
                    .padding(.trailing, 20)
                
                // Action Button
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        welcomeComplete = true
                    }
                } label: {
                    Text("Continue to Next")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(DS.coralGradient())
                        )
                }
                .buttonStyle(.plain)
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 32)
        }
    }
}
