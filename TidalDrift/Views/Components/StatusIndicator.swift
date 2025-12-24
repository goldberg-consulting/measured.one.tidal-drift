import SwiftUI

struct StatusIndicator: View {
    let isOnline: Bool
    var size: CGFloat = 10
    var animated: Bool = true
    
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            if isOnline && animated {
                Circle()
                    .stroke(Color.green, lineWidth: 2)
                    .frame(width: size * 1.5, height: size * 1.5)
                    .scaleEffect(isPulsing ? 1.5 : 1)
                    .opacity(isPulsing ? 0 : 0.5)
            }
            
            Circle()
                .fill(isOnline ? Color.green : Color.gray)
                .frame(width: size, height: size)
        }
        .onAppear {
            if isOnline && animated {
                withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
        }
        .onChange(of: isOnline) { newValue in
            if newValue && animated {
                withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            } else {
                isPulsing = false
            }
        }
    }
}

struct PulsingCircle: View {
    let color: Color
    var size: CGFloat = 12
    
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: size * 2, height: size * 2)
                .scaleEffect(isPulsing ? 2 : 1)
                .opacity(isPulsing ? 0 : 0.6)
            
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

struct LoadingIndicator: View {
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Color.accentColor, lineWidth: 2)
            .frame(width: 20, height: 20)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

struct StatusIndicator_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                StatusIndicator(isOnline: true)
                StatusIndicator(isOnline: false)
                StatusIndicator(isOnline: true, size: 16)
            }
            
            HStack(spacing: 20) {
                PulsingCircle(color: .green)
                PulsingCircle(color: .blue)
                PulsingCircle(color: .orange)
            }
            
            LoadingIndicator()
        }
        .padding()
    }
}
