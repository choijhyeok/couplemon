import SwiftUI

struct PetLevelBar: View {
    let progress: PetProgress
    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text("LV \(progress.level)").fontWeight(.bold)
                Spacer(minLength: 0)
                Text(progress.requiredExperience == 0 ? "MAX" : "\(progress.currentExperience) / \(progress.requiredExperience) XP")
                    .monospacedDigit()
            }.font(.system(size: 10, design: .rounded))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(LinearGradient(colors: [.pink, .yellow], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * progress.fraction)
                }
            }.frame(height: 4)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .frame(width: 166)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("레벨 \(progress.level), 경험치 \(progress.currentExperience) / \(progress.requiredExperience)")
        .help("채팅 +10 · 그림 +25 · 이모지 +5 XP\n최대 LV 100 · 매 레벨 아이템·상호작용 해금")
    }
}
