import SwiftUI

struct PetActionPanel: View {
    @ObservedObject var model: AppModel
    var onClose: () -> Void
    @ObservedObject private var together: CouplePetSession
    init(model: AppModel, onClose: @escaping () -> Void) {
        self.model = model; self.onClose = onClose; together = model.together
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab = 0
    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("행동", systemImage: "sparkles").font(.subheadline.bold())
                Spacer()
                Text("LV \(model.petProgress.level)").font(.caption.bold()).foregroundStyle(.secondary)
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("행동 창 닫기")
            }
            HStack {
                Button(model.isRandom3DEnabled ? "자동 중지" : "랜덤 행동",
                       systemImage: model.isRandom3DEnabled ? "pause.fill" : "shuffle") {
                    model.setRandom3DEnabled(!model.isRandom3DEnabled)
                }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(model.isRandom3DEnabled ? "랜덤 행동 자동 중지" : "랜덤 행동 자동 시작")
                Menu {
                    Picker("동작 사이 휴식 간격", selection: Binding(get: { model.random3DInterval }, set: model.setRandom3DInterval)) {
                        ForEach(AppModel.random3DIntervals, id: \.self) { Text("\($0)초").tag($0) }
                    }
                } label: {
                    Text("\(model.random3DInterval)초").font(.caption.monospacedDigit())
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("동작이 끝난 뒤 다음 랜덤 행동까지의 휴식 간격")
                Spacer()
                Button("기본", systemImage: "leaf") { model.play3DAction(.idle) }
            }
            .controlSize(.small)
            Picker("행동 종류", selection: $selectedTab) {
                Text("기본").tag(0)
                Text("도구 \(model.unlockedRewards.count)").tag(1)
                Text("함께하기").tag(2)
            }.pickerStyle(.segmented).controlSize(.small)
            if reduceMotion {
                Text("macOS 동작 줄이기 설정으로 애니메이션이 제한됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                  if selectedTab == 2 {
                    Label(together.partnerName, systemImage: "person.2.fill").font(.caption.bold())
                    Text(together.status).font(.caption).foregroundStyle(.secondary)
                    if let progress = together.progress { ProgressView(value: progress) }
                    ForEach(CouplePetAction.allCases) { action in
                        actionButton(action.title, symbol: action.symbol) { together.perform(action) }
                            .disabled(!together.canInteract)
                    }
                    Text("양쪽에서 8MB 이하 3D 캐릭터를 선택하면 자동 공유됩니다. 함께하는 동안 랜덤 행동은 잠시 쉬어요.")
                        .font(.caption2).foregroundStyle(.secondary)
                  } else if selectedTab == 0 {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Pet3DAction.basicActions.filter { $0 != .idle }) { action in
                            actionButton(action.title, symbol: action.symbolName,
                                         selected: model.petActivity?.action3D == action) { model.play3DAction(action) }
                        }
                    }
                  } else {
                    if model.unlockedRewards.isEmpty {
                        Label("LV 2에서 별 장난감과 별 돌리기가 해금됩니다.", systemImage: "lock.fill")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.vertical, 20)
                    } else {
                        Text("누르면 해당 도구를 장착하고 연결 동작을 재생합니다.")
                            .font(.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 7) {
                            ForEach(model.unlockedRewards) { reward in
                                actionButton("LV \(reward.level) · \(reward.kind.title)", symbol: reward.action.symbolName,
                                             selected: model.equippedRewardLevel == reward.level) {
                                    model.playRewardInteraction(at: reward.level)
                                }
                                .help("\(reward.title) · \(reward.action.title)")
                            }
                        }
                    }
                    if let next = PetLevelReward.reward(at: model.petProgress.level + 1) {
                        Label("다음 해금: LV \(next.level) · \(next.kind.title)", systemImage: "lock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                  }
                }.padding(.vertical, 2)
            }
            Text(model.isRandom3DEnabled
                 ? "동작 종료 후 \(model.random3DInterval)초 쉬고 반복 · XP 적립 없음"
                 : "랜덤 행동을 켜면 주기적으로 계속 움직입니다.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 252, height: 330)
    }

    private func actionButton(_ title: String, symbol: String, selected: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).frame(width: 14)
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
            }
            .padding(.horizontal, 7).frame(maxWidth: .infinity, minHeight: 32)
            .background(selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

extension Pet3DAction {
    var symbolName: String {
        switch self {
        case .idle: "leaf"
        case .runningRight, .runningLeft, .running: "figure.run"
        case .waving: "hand.wave"
        case .jumping: "figure.jumprope"
        case .failed: "cloud.rain"
        case .waiting: "hourglass"
        case .review: "book"
        case .lookAround: "eyes"
        case .playStar: "star"
        case .hugHeart: "heart"
        case .blowBubbles: "bubbles.and.sparkles"
        case .restMoon: "moon"
        case .playBall: "basketball"
        case .paint: "paintbrush"
        case .playMusic: "music.note"
        case .fish: "fish"
        case .celebrateCrown: "crown"
        case .castSpell: "wand.and.stars"
        case .celebrate100: "trophy"
        }
    }
}
