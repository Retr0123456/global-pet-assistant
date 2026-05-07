import AppKit

enum PetDragDirection {
    case left
    case right

    var animationState: PetAnimationState {
        switch self {
        case .left:
            .runningLeft
        case .right:
            .runningRight
        }
    }
}

@MainActor
final class PetBehaviorController {
    private let spriteView: PetSpriteView
    private var baseState: PetAnimationState = .idle
    private var isHovering = false
    private var transientTimer: Timer?
    private var transientToken = 0
    private var isPlayingTransient = false
    private var dragDirection: PetDragDirection?

    init(spriteView: PetSpriteView) {
        self.spriteView = spriteView
        spriteView.playLoop(baseState)
    }

    func replaceAtlas(_ atlas: PetAtlas) {
        let steadyState = dragDirection?.animationState ?? (isHovering ? .jumping : baseState)
        spriteView.replaceAtlas(atlas, preserving: steadyState)
    }

    func setBaseState(_ state: PetAnimationState) {
        baseState = state
        guard dragDirection == nil, !isPlayingTransient, !isHovering else {
            return
        }

        spriteView.playLoop(baseState)
    }

    func handleHoverChanged(isInside: Bool) {
        guard isHovering != isInside else {
            return
        }

        isHovering = isInside
        guard dragDirection == nil, !isPlayingTransient else {
            return
        }

        spriteView.playLoop(isHovering ? .jumping : baseState)
    }

    func handleClick(hasAction: Bool, performAction: () -> Bool) {
        guard dragDirection == nil else {
            return
        }

        if hasAction {
            if performAction() {
                playBriefLoop(.review, duration: 1.25)
            }
        } else {
            playReaction(.jumping)
        }
    }

    func handleFlash(level: PetEventLevel, state: PetAnimationState) {
        guard dragDirection == nil else {
            return
        }

        let animationState: PetAnimationState
        switch level {
        case .danger:
            animationState = .failed
        case .success:
            animationState = state == .review ? .waving : state
        case .warning, .running, .info:
            animationState = state
        }

        playBriefLoop(animationState, duration: 1.2)
    }

    func handleDragChanged(direction: PetDragDirection?) {
        guard let direction else {
            if dragDirection != nil {
                dragDirection = nil
                cancelTransient()
                resumeSteadyAnimation()
            }
            return
        }

        guard dragDirection != direction else {
            return
        }

        dragDirection = direction
        cancelTransient()
        spriteView.playLoop(direction.animationState)
    }

    func previewState(_ state: PetAnimationState, duration: TimeInterval = 5.0) {
        guard dragDirection == nil else {
            return
        }

        transientToken += 1
        let token = transientToken
        isPlayingTransient = true
        transientTimer?.invalidate()
        spriteView.playLoop(state)

        transientTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.transientToken == token else {
                    return
                }

                self.isPlayingTransient = false
                if self.dragDirection == nil {
                    self.spriteView.playLoop(self.baseState)
                }
            }
        }
    }

    private func playReaction(_ state: PetAnimationState) {
        guard dragDirection == nil, !isPlayingTransient else {
            return
        }

        transientToken += 1
        let token = transientToken
        isPlayingTransient = true

        spriteView.playOnce(state) { [weak self] in
            guard let self, self.transientToken == token else {
                return
            }

            self.isPlayingTransient = false
            if self.dragDirection == nil {
                self.resumeSteadyAnimation()
            }
        }
    }

    private func playBriefLoop(_ state: PetAnimationState, duration: TimeInterval) {
        guard dragDirection == nil else {
            return
        }

        transientToken += 1
        let token = transientToken
        isPlayingTransient = true
        transientTimer?.invalidate()
        spriteView.playLoop(state)

        transientTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.transientToken == token else {
                    return
                }

                self.isPlayingTransient = false
                if self.dragDirection == nil {
                    self.resumeSteadyAnimation()
                }
            }
        }
    }

    private func cancelTransient() {
        transientToken += 1
        isPlayingTransient = false
        transientTimer?.invalidate()
        transientTimer = nil
    }

    private func resumeSteadyAnimation() {
        spriteView.playLoop(isHovering ? .jumping : baseState)
    }
}
