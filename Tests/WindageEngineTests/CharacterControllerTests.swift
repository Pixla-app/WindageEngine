//
//  CharacterControllerTests.swift
//  WindageEngineTests
//

import Testing
import simd
@testable import WindageEngine

/// A hillside that is rough everywhere: a long slope, plus bumps at two scales. Stands in for the
/// fractal terrain the walking half was tuned on — what matters is that there is always a bump.
private let hillside: @Sendable (Float, Float) -> Float = { x, z in
    -z * 0.18 + 0.35 * sin(x * 0.9) * cos(z * 1.3) + 0.08 * sin(x * 5.1 + z * 4.3)
}

private let step: Float = 1.0 / 120
private let flat = CharacterController.Surroundings()

private func run(_ controller: inout CharacterController,
                 seconds: Float,
                 yaw: Float = 0,
                 _ input: MovementInput = MovementInput(),
                 jump: Bool = false,
                 crouching: Bool = false,
                 in world: CharacterController.Surroundings = flat) {
    for _ in 0..<Int((seconds / step).rounded()) {
        controller.step(yaw: yaw, input: input, jump: jump, crouching: crouching,
                        deltaTime: step, in: world)
    }
}

private func ground(_ p: SIMD3<Float>) -> SIMD2<Float> { SIMD2(p.x, p.z) }

/// A box standing on the ground at the origin's z, `height` tall, starting `ahead` metres in front.
private func ledge(height: Float, ahead: Float = 2, depth: Float = 4) -> BoundingBox {
    BoundingBox(minimum: SIMD3(-3, 0, -ahead - depth), maximum: SIMD3(3, height, -ahead))
}

// MARK: - Walking, carried over

@Suite("Character controller — walking")
struct CharacterWalkingTests {

    private var forwards: MovementInput { MovementInput(forward: 1) }

    /// **The bug the free-flying camera had.** Walking along the look direction means aiming at your
    /// feet walks you into the hill at `cos θ`. The controller never sees pitch; this pins it.
    @Test("The walk speed is the walk speed, on the level")
    func walkSpeedIsExact() {
        var c = CharacterController(feet: .zero)
        run(&c, seconds: 2, forwards)
        let crossed = simd_distance(ground(c.feet), .zero)
        let expected = Float(Int((2 / step).rounded())) * step * c.tuning.walkSpeed
        #expect(abs(crossed - expected) < 0.01, "crossed \(crossed) m rather than \(expected)")
    }

    /// Horizontal speed is the same downhill, uphill and across. A shooter that drags on an incline
    /// feels broken.
    @Test("The slope does not change how fast the ground goes by")
    func slopeDoesNotChangeGroundSpeed() {
        let world = CharacterController.Surroundings(groundHeight: hillside)
        for (name, yaw) in [("uphill", Float(0)), ("downhill", Float.pi), ("across", Float.pi / 2)] {
            var c = CharacterController(feet: SIMD3(0, hillside(0, 0), 0))
            run(&c, seconds: 1.5, yaw: yaw, forwards, in: world)
            let crossed = simd_distance(ground(c.feet), .zero)
            let expected = Float(Int((1.5 / step).rounded())) * step * c.tuning.walkSpeed
            #expect(abs(crossed - expected) < 0.01, "\(name): crossed \(crossed) m against \(expected)")
        }
    }

    @Test("The feet stay on the terrain, and the eye stays near its height above it")
    func followsTheGround() {
        let world = CharacterController.Surroundings(groundHeight: hillside)
        var c = CharacterController(feet: SIMD3(0, hillside(0, 0), 0))
        var worst: Float = 0
        for _ in 0..<(120 * 10) {
            c.step(yaw: 0, input: forwards, deltaTime: step, in: world)
            #expect(abs(c.feet.y - hillside(c.feet.x, c.feet.z)) < 1e-4)
            worst = max(worst, abs(c.eye.y - hillside(c.feet.x, c.feet.z) - c.tuning.eyeHeight))
        }
        #expect(c.isGrounded)
        #expect(worst < 0.35, "the eye drifted \(worst) m from its standing height")
    }

    /// **Settling, not snapping.** There is always a bump; tracking it exactly at 120 Hz reads as a
    /// jitter.
    @Test("The eye is steadier than the ground")
    func eyeIsSteadierThanTheGround() {
        let world = CharacterController.Surroundings(groundHeight: hillside)
        var c = CharacterController(feet: SIMD3(0, hillside(0, 0), 0))
        var eyeJerk: Float = 0, groundJerk: Float = 0
        var previousEye = c.eye.y, previousGround = c.feet.y
        for _ in 0..<(120 * 4) {
            c.step(yaw: .pi / 2, input: forwards, deltaTime: step, in: world)
            eyeJerk = max(eyeJerk, abs(c.eye.y - previousEye))
            groundJerk = max(groundJerk, abs(c.feet.y - previousGround))
            previousEye = c.eye.y
            previousGround = c.feet.y
        }
        #expect(eyeJerk < groundJerk, "the eye moved \(eyeJerk) m a step against the ground's \(groundJerk)")
    }

    /// **Normalising the direction threw the deflection away**: every push past the dead zone walked
    /// at full speed, so the stick's response curve reached the look and never the feet.
    @Test("A stick pushed part of the way walks part of the speed")
    func stickPartWayWalksPartSpeed() {
        var c = CharacterController(feet: .zero)
        run(&c, seconds: 1, MovementInput(forward: 0.3))
        #expect(abs(simd_length(ground(c.feet)) - 1.8) < 0.01,
                "a stick at 0.3 should cover 0.3 of 6 m, not all of it: \(simd_length(ground(c.feet)))")
        var camera = Camera()
        for _ in 0..<120 { camera.advance(MovementInput(forward: 0.3), deltaTime: step) }
        #expect(abs(simd_length(camera.position) - 1.8) < 0.01, "the flying camera had the same fault")
    }

    @Test("Walking diagonally is not faster")
    func diagonalIsNotFaster() {
        var straight = CharacterController(feet: .zero)
        var angled = CharacterController(feet: .zero)
        run(&straight, seconds: 1, forwards)
        run(&angled, seconds: 1, MovementInput(forward: 1, strafe: 1))
        #expect(abs(simd_length(ground(straight.feet)) - simd_length(ground(angled.feet))) < 0.05)
    }

    @Test("No input means no movement")
    func standingStillIsStill() {
        var c = CharacterController(feet: SIMD3(2, 0, 3))
        run(&c, seconds: 3)
        #expect(c.feet == SIMD3(2, 0, 3))
        #expect(c.isGrounded)
    }
}

// MARK: - Crouch and slide, carried over

@Suite("Character controller — crouch and slide")
struct CharacterPostureTests {

    private var running: MovementInput { MovementInput(forward: 1, sprint: true) }

    @Test("Crouching lowers the eye and standing raises it again")
    func postureChanges() {
        var c = CharacterController(feet: .zero)
        run(&c, seconds: 2, crouching: true)
        #expect(abs(c.eye.y - c.tuning.crouchedEyeHeight) < 0.02)
        run(&c, seconds: 2)
        #expect(abs(c.eye.y - c.tuning.eyeHeight) < 0.02)
    }

    @Test("The posture moves at a rate, not instantly")
    func postureIsNotATeleport() {
        var c = CharacterController(feet: .zero)
        let before = c.eye.y
        c.step(yaw: 0, input: MovementInput(), crouching: true, deltaTime: step, in: flat)
        let moved = before - c.eye.y
        #expect(moved > 0)
        #expect(moved < c.tuning.postureRate * step * 1.5)
    }

    /// **The cost. Without it the posture is free and you would simply hold it.**
    @Test("Crouched you move much slower, and cannot sprint")
    func crouchingCostsSpeed() {
        var standing = CharacterController(feet: .zero)
        var crouched = CharacterController(feet: .zero)
        var sprintCrouched = CharacterController(feet: .zero)
        run(&standing, seconds: 2, MovementInput(forward: 1))
        run(&crouched, seconds: 2, MovementInput(forward: 1), crouching: true)
        run(&sprintCrouched, seconds: 2, running, crouching: true)
        let a = simd_length(ground(standing.feet)), b = simd_length(ground(crouched.feet))
        #expect(b < a * 0.6)
        #expect(abs(simd_length(ground(sprintCrouched.feet)) - b) < 0.01, "sprint worked from a crouch")
    }

    /// Sprints, then crouches, and reports how far the slide carried and how long it lasted.
    private func slide(steering input: MovementInput? = nil)
        -> (distance: Float, seconds: Float, controller: CharacterController, start: SIMD2<Float>) {
        var c = CharacterController(feet: .zero)
        run(&c, seconds: 1, running)
        let start = ground(c.feet)
        var seconds: Float = 0
        // `repeat`: the slide only exists after the first crouching step.
        repeat {
            c.step(yaw: 0, input: input ?? running, crouching: true, deltaTime: step, in: flat)
            seconds += step
        } while c.isSliding && seconds < 5
        return (simd_distance(ground(c.feet), start), seconds, c, start)
    }

    @Test("Crouching while sprinting slides instead of stopping")
    func itSlides() {
        let result = slide()
        let crouchWalk = CharacterController.Tuning().walkSpeed
            * CharacterController.Tuning().crouchedSpeedFraction * result.seconds
        #expect(result.distance > crouchWalk * 2, "no momentum: \(result.distance) m")
        #expect(abs(result.seconds - CharacterController.Tuning().slideSeconds) < 0.05)
        // Momentum, not a way to travel.
        #expect(result.distance < 18, "a \(result.distance) m slide is a way of getting places")
    }

    @Test("Holding crouch does not restart the slide")
    func slideDoesNotChain() {
        var c = slide().controller
        for _ in 0..<600 {
            c.step(yaw: 0, input: running, crouching: true, deltaTime: step, in: flat)
            #expect(!c.isSliding)
        }
    }

    @Test("You cannot slide from a standstill or a walk")
    func slideNeedsSprintSpeed() {
        var still = CharacterController(feet: .zero)
        still.step(yaw: 0, input: MovementInput(), crouching: true, deltaTime: step, in: flat)
        #expect(!still.isSliding)

        var walking = CharacterController(feet: .zero)
        run(&walking, seconds: 1, MovementInput(forward: 1))
        walking.step(yaw: 0, input: MovementInput(forward: 1), crouching: true, deltaTime: step, in: flat)
        #expect(!walking.isSliding)
    }

    /// **Committed.** Entered running down −Z with a hard left demanded throughout.
    @Test("A slide goes where it was entered, not where the stick says")
    func slideIsCommitted() {
        let result = slide(steering: MovementInput(strafe: -1, sprint: true))
        let travel = ground(result.controller.feet) - result.start
        #expect(travel.y < -8, "it barely carried forward: \(travel)")
        #expect(abs(travel.x) < abs(travel.y) * 0.4, "that is steering, not sliding: \(travel)")
        #expect(abs(travel.x) > 0.3, "no influence at all — a rail: \(travel)")
    }

    @Test("The slide's camera dip peaks early and recovers")
    func dipRecovers() {
        var c = CharacterController(feet: .zero)
        run(&c, seconds: 1, running)
        #expect(c.slideCameraDip == 0)
        var samples: [Float] = []
        repeat {
            c.step(yaw: 0, input: running, crouching: true, deltaTime: step, in: flat)
            samples.append(c.slideCameraDip)
        } while c.isSliding
        let peak = samples.min() ?? 0
        #expect(peak < -0.05)
        #expect(c.slideCameraDip == 0)
        #expect((samples.firstIndex(of: peak) ?? samples.count) < samples.count / 3)
    }
}

// MARK: - Standing on things: new

@Suite("Character controller — standing on things")
struct CharacterFootingTests {

    private var forwards: MovementInput { MovementInput(forward: 1) }

    /// **Stairs.** Below the step height, a ledge is walked up without a jump, and the feet end up
    /// exactly on its top.
    @Test("A ledge below the step height is walked onto")
    func stepsUpALowLedge() {
        let world = CharacterController.Surroundings(solids: [ledge(height: 0.3)])
        var c = CharacterController(feet: .zero)
        run(&c, seconds: 1, forwards, in: world)
        #expect(c.feet.z < -2.5, "it did not get onto the ledge: \(c.feet)")
        #expect(abs(c.feet.y - 0.3) < 1e-4)
        #expect(c.isGrounded)
    }

    /// **A crate is cover.** Taller than a step, it stops you, and you stay on the ground in front of
    /// it rather than climbing it or sinking into it.
    @Test("A crate taller than the step height stops you")
    func crateStops() {
        let crate = ledge(height: 1.5)
        let world = CharacterController.Surroundings(solids: [crate])
        var c = CharacterController(feet: .zero)
        run(&c, seconds: 2, forwards, in: world)
        #expect(c.feet.y == 0)
        #expect(c.feet.z >= crate.maximum.z + c.tuning.radius - 1e-3,
                "walked into the crate: feet at \(c.feet.z), face at \(crate.maximum.z)")
        #expect(c.feet.z < crate.maximum.z + c.tuning.radius + 0.05,
                "stopped short of the crate: \(c.feet.z)")
    }

    /// **Met, not stopped short of.** Refusing a blocked step outright leaves the player wherever
    /// the last whole step ended — found in the sample as a 4 cm gap at a walk and 15 cm at a sprint.
    @Test("Running into a wall ends touching it, at a walk or a sprint")
    func wallIsMet() {
        let crate = ledge(height: 1.5)
        let world = CharacterController.Surroundings(solids: [crate])
        for input in [MovementInput(forward: 1), MovementInput(forward: 1, sprint: true)] {
            var c = CharacterController(feet: .zero)
            run(&c, seconds: 1, input, in: world)
            let gap = c.feet.z - (crate.maximum.z + c.tuning.radius)
            #expect(gap >= 0 && gap < 0.01, "\(input.sprint ? "sprinting" : "walking"): \(gap) m short")
        }
    }

    /// **Walking into a wall at an angle slides along it.** Refusing the whole move is what makes a
    /// wall feel like glue — and is also the only way out of a corner.
    @Test("A wall hit at an angle is slid along, not stuck to")
    func slidesAlongWalls() {
        let wall = BoundingBox(minimum: SIMD3(-50, 0, -2), maximum: SIMD3(50, 3, -1))
        let world = CharacterController.Surroundings(solids: [wall])
        var c = CharacterController(feet: .zero)
        // Forward and right at once, into a wall that runs left–right.
        run(&c, seconds: 2, MovementInput(forward: 1, strafe: 1), in: world)
        #expect(c.feet.x > 5, "it stuck to the wall: \(c.feet)")
        #expect(c.feet.z > -1 + c.tuning.radius - 1e-3)
    }

    /// **Walking off an edge falls**, and lands on whatever is below.
    @Test("Walking off something taller than a step falls, and lands")
    func fallsOffAnEdge() {
        let platform = BoundingBox(minimum: SIMD3(-3, 0, -3), maximum: SIMD3(3, 1.2, 3))
        let world = CharacterController.Surroundings(solids: [platform])
        var c = CharacterController(feet: SIMD3(0, 1.2, 0))
        var wasAirborne = false
        for _ in 0..<(120 * 2) {
            c.step(yaw: 0, input: forwards, deltaTime: step, in: world)
            if !c.isGrounded { wasAirborne = true }
        }
        #expect(wasAirborne, "it walked off a 1.2 m drop without leaving the ground")
        #expect(c.isGrounded)
        #expect(c.feet.y == 0)
        #expect(c.feet.z < -3)
    }

    /// Down a step is not a fall: the feet follow it, and the eye eases after them.
    @Test("Stepping down a low ledge stays grounded")
    func stepsDown() {
        let platform = BoundingBox(minimum: SIMD3(-3, 0, -3), maximum: SIMD3(3, 0.3, 3))
        let world = CharacterController.Surroundings(solids: [platform])
        var c = CharacterController(feet: SIMD3(0, 0.3, 0))
        for _ in 0..<(120 * 2) {
            c.step(yaw: 0, input: forwards, deltaTime: step, in: world)
            #expect(c.isGrounded, "a 30 cm step down became a fall at \(c.feet)")
        }
        #expect(c.feet.y == 0)
    }

    /// **The feet move at once; the eye follows.** Stairs that snapped the eye would stutter.
    @Test("Stepping up moves the feet at once and the eye over a moment")
    func eyeEasesUpAStep() {
        let world = CharacterController.Surroundings(solids: [ledge(height: 0.4, ahead: 0.5)])
        var c = CharacterController(feet: .zero)
        var eyeRise: [Float] = []
        var previous = c.eye.y
        for _ in 0..<60 {
            c.step(yaw: 0, input: forwards, deltaTime: step, in: world)
            eyeRise.append(c.eye.y - previous)
            previous = c.eye.y
        }
        #expect(abs(c.feet.y - 0.4) < 1e-4)
        #expect((eyeRise.max() ?? 0) < 0.2, "the eye jumped \(eyeRise.max() ?? 0) m in one step")
    }

    @Test("A jump clears a low wall but not a crate")
    func jumpHeight() {
        var c = CharacterController(feet: .zero)
        var apex: Float = 0
        c.step(yaw: 0, input: MovementInput(), jump: true, deltaTime: step, in: flat)
        for _ in 0..<(120 * 2) {
            c.step(yaw: 0, input: MovementInput(), jump: true, deltaTime: step, in: flat)
            apex = max(apex, c.feet.y)
        }
        #expect(apex > 0.9 && apex < 1.2, "a jump reached \(apex) m")
        #expect(c.isGrounded)
    }

    /// **Holding jump is one jump.** Without the edge, holding the key bounces for ever.
    @Test("Holding jump does not bounce")
    func holdingJumpIsOneJump() {
        var c = CharacterController(feet: .zero)
        var takeoffs = 0
        var wasGrounded = true
        for _ in 0..<(120 * 3) {
            c.step(yaw: 0, input: MovementInput(), jump: true, deltaTime: step, in: flat)
            if wasGrounded && !c.isGrounded { takeoffs += 1 }
            wasGrounded = c.isGrounded
        }
        #expect(takeoffs == 1)
    }

    /// **Coyote time.** A jump pressed just after running off an edge still counts.
    @Test("A jump just after leaving an edge still jumps")
    func coyoteTime() {
        let platform = BoundingBox(minimum: SIMD3(-3, 0, -3), maximum: SIMD3(3, 1.2, 0))
        let world = CharacterController.Surroundings(solids: [platform])
        var c = CharacterController(feet: SIMD3(0, 1.2, -1))
        // Walk off the +z edge (yaw π faces +z) until airborne, then press jump two steps later.
        while c.isGrounded { c.step(yaw: .pi, input: forwards, deltaTime: step, in: world) }
        c.step(yaw: .pi, input: forwards, deltaTime: step, in: world)
        let before = c.verticalVelocity
        c.step(yaw: .pi, input: forwards, jump: true, deltaTime: step, in: world)
        #expect(c.verticalVelocity > before + 3, "the late jump was eaten: \(c.verticalVelocity)")
    }

    /// **Jump buffering.** Pressed a moment before landing, it jumps on landing.
    @Test("A jump pressed just before landing jumps on landing")
    func jumpBuffer() {
        var c = CharacterController(feet: SIMD3(0, 0.6, 0))
        c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: flat)   // falling
        while c.feet.y > 0.08 { c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: flat) }
        c.step(yaw: 0, input: MovementInput(), jump: true, deltaTime: step, in: flat)  // pressed in the air
        var rose = false
        for _ in 0..<12 {
            c.step(yaw: 0, input: MovementInput(), jump: false, deltaTime: step, in: flat)
            if c.verticalVelocity > 3 { rose = true }
        }
        #expect(rose, "a jump pressed just before landing was lost")
    }

    @Test("No jump out of a slide")
    func noJumpFromSlide() {
        var c = CharacterController(feet: .zero)
        run(&c, seconds: 1, MovementInput(forward: 1, sprint: true))
        c.step(yaw: 0, input: MovementInput(forward: 1, sprint: true), crouching: true,
               deltaTime: step, in: flat)
        #expect(c.isSliding)
        c.step(yaw: 0, input: MovementInput(forward: 1, sprint: true), jump: true, crouching: true,
               deltaTime: step, in: flat)
        #expect(c.isGrounded)
    }

    /// A head against the underside of something stops the rise, rather than passing through.
    @Test("A jump under a low ceiling stops at the ceiling")
    func ceilingStopsAJump() {
        let ceiling = BoundingBox(minimum: SIMD3(-3, 2.2, -3), maximum: SIMD3(3, 2.5, 3))
        let world = CharacterController.Surroundings(solids: [ceiling])
        var c = CharacterController(feet: .zero)
        var highestHead: Float = 0
        c.step(yaw: 0, input: MovementInput(), jump: true, deltaTime: step, in: world)
        for _ in 0..<120 {
            c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: world)
            highestHead = max(highestHead, c.bounds.maximum.y)
        }
        #expect(highestHead <= 2.2 + 1e-3, "the head reached \(highestHead) m into a ceiling at 2.2")
        #expect(c.isGrounded)
    }

    /// **A fast fall cannot skip a thin floor.** Landing is measured from where the feet were.
    @Test("A long fall lands on a thin platform rather than passing through it")
    func fastFallLands() {
        let slab = BoundingBox(minimum: SIMD3(-3, 4.95, -3), maximum: SIMD3(3, 5, 3))
        let world = CharacterController.Surroundings(solids: [slab])
        var c = CharacterController(feet: SIMD3(0, 60, 0))
        run(&c, seconds: 4, in: world)
        #expect(abs(c.feet.y - 5) < 1e-4, "fell to \(c.feet.y)")
        #expect(c.isGrounded)
    }

    /// Standing on a crate and walking across it is not walking into it.
    @Test("Walking across the top of a solid is not blocked by it")
    func walksAcrossATop() {
        let top = BoundingBox(minimum: SIMD3(-5, 0, -20), maximum: SIMD3(5, 1.5, 5))
        let world = CharacterController.Surroundings(solids: [top])
        var c = CharacterController(feet: SIMD3(0, 1.5, 0))
        run(&c, seconds: 2, forwards, in: world)
        #expect(c.feet.z < -10)
        #expect(abs(c.feet.y - 1.5) < 1e-4)
    }
}

// MARK: - Footfalls and landings

@Suite("Character controller — what it reports")
struct CharacterEventTests {

    private func strides(_ c: inout CharacterController, seconds: Float, _ input: MovementInput,
                         crouching: Bool = false,
                         in world: CharacterController.Surroundings = flat) -> [CharacterController.Event] {
        var all: [CharacterController.Event] = []
        for _ in 0..<Int((seconds / step).rounded()) {
            c.step(yaw: 0, input: input, crouching: crouching, deltaTime: step, in: world)
            all += c.events
        }
        return all
    }

    private func strideCount(_ events: [CharacterController.Event]) -> Int {
        events.filter { if case .stride = $0 { true } else { false } }.count
    }

    /// A cadence the ear takes for feet: about two a second walking, more sprinting, fewer crouched.
    @Test("Walking, sprinting and crouching step at different rates")
    func cadence() {
        var walk = CharacterController(feet: .zero)
        var sprint = CharacterController(feet: .zero)
        var crouch = CharacterController(feet: .zero)
        let w = strideCount(strides(&walk, seconds: 4, MovementInput(forward: 1))) / 4
        let s = strideCount(strides(&sprint, seconds: 4, MovementInput(forward: 1, sprint: true))) / 4
        let c = strideCount(strides(&crouch, seconds: 4, MovementInput(forward: 1), crouching: true)) / 4
        #expect(w >= 2 && w <= 3, "walking \(w) a second")
        #expect(s > w, "sprinting \(s) against walking \(w)")
        #expect(c < w, "crouched \(c) against walking \(w)")
    }

    /// **Distance covered, not asked for.** Pushing into a wall asks for six metres a second.
    @Test("Walking into a wall does not march on the spot")
    func noStepsAgainstAWall() {
        let world = CharacterController.Surroundings(solids: [ledge(height: 2, ahead: 0.35)])
        var c = CharacterController(feet: .zero)
        _ = strides(&c, seconds: 0.5, MovementInput(forward: 1), in: world)     // reach the wall
        let pressed = strides(&c, seconds: 3, MovementInput(forward: 1), in: world)
        #expect(strideCount(pressed) == 0, "\(strideCount(pressed)) footsteps against a wall")
    }

    @Test("Standing still makes no footsteps")
    func stillIsSilent() {
        var c = CharacterController(feet: .zero)
        #expect(strides(&c, seconds: 3, MovementInput()).isEmpty)
    }

    /// Not a whole stride's silence after the key goes down.
    @Test("The first footstep comes soon after setting off")
    func firstStepIsPrompt() {
        var c = CharacterController(feet: .zero)
        var seconds: Float = 0
        while seconds < 2 {
            c.step(yaw: 0, input: MovementInput(forward: 1), deltaTime: step, in: flat)
            seconds += step
            if c.events.contains(where: { if case .stride = $0 { true } else { false } }) { break }
        }
        let strideTime = c.tuning.walkStride / c.tuning.walkSpeed
        #expect(seconds < strideTime * 0.6, "the first step took \(seconds) s of a \(strideTime) s stride")
    }

    /// **A foot on every tread.** Distance alone climbs a flight of stairs in half the footsteps,
    /// because a stride at these speeds is longer than a tread.
    @Test("Climbing stairs sounds a foot on each tread")
    func stairsGetAFootEach() {
        // Four 0.3 m treads, 1 m deep, rising away along −z.
        var treads: [BoundingBox] = []
        for i in 0..<4 {
            let near = -Float(i + 1), far = -Float(i + 2), top = 0.3 * Float(i + 1)
            treads.append(BoundingBox(minimum: SIMD3<Float>(-3, 0, far), maximum: SIMD3<Float>(3, top, near)))
        }
        let landing = BoundingBox(minimum: SIMD3(-3, 0, -12), maximum: SIMD3(3, 1.2, -5))
        var c = CharacterController(feet: .zero)
        var climbSteps = 0
        for _ in 0..<(120 * 2) {
            let before = c.feet.y
            c.step(yaw: 0, input: MovementInput(forward: 1), deltaTime: step,
                   in: CharacterController.Surroundings(solids: treads + [landing]))
            let rose = c.feet.y > before + 0.1
            if rose && c.events.contains(where: { if case .stride = $0 { true } else { false } }) {
                climbSteps += 1
            }
        }
        #expect(abs(c.feet.y - 1.2) < 1e-4)
        #expect(climbSteps >= 4, "\(climbSteps) footsteps for four treads")
    }

    /// **The mirror of the climb**: descending the same four treads sounded one footstep until 0.10.3,
    /// against the climb's four. Walked from mirrored starts — a metre short of the stairs either way —
    /// so the stride arrives at the first tread edge in the same phase, down as well as up.
    @Test("Coming down stairs sounds as many footsteps on the treads as going up")
    func descendingMatchesClimbing() {
        var treads: [BoundingBox] = []
        for i in 0..<4 {
            let near = -Float(i + 1), far = -Float(i + 2), top = 0.3 * Float(i + 1)
            treads.append(BoundingBox(minimum: SIMD3<Float>(-3, 0, far), maximum: SIMD3<Float>(3, top, near)))
        }
        let landing = BoundingBox(minimum: SIMD3(-3, 0, -12), maximum: SIMD3(3, 1.2, -5))
        let world = CharacterController.Surroundings(solids: treads + [landing])
        func treadSteps(from start: SIMD3<Float>, yaw: Float) -> Int {
            var c = CharacterController(feet: start)
            var count = 0
            for _ in 0..<240 {
                let before = c.feet.y
                c.step(yaw: yaw, input: MovementInput(forward: 1), deltaTime: step, in: world)
                if abs(c.feet.y - before) > 0.1 && c.events.contains(where: { if case .stride = $0 { true } else { false } }) {
                    count += 1
                }
            }
            return count
        }
        let up = treadSteps(from: SIMD3(0, 0, 0), yaw: 0)
        let down = treadSteps(from: SIMD3(0, 1.2, -6), yaw: .pi)
        #expect(up >= 3, "the climb itself: \(up)")
        #expect(down == up, "\(down) footsteps coming down four treads, \(up) going up")
    }

    /// A gentle slope is not stairs, in either direction: no extra footfalls going down one.
    @Test("Walking down a slope keeps its ordinary stride")
    func slopeDownIsNotStairs() {
        let slope = CharacterController.Surroundings(groundHeight: { _, z in 0.15 * z })
        var c = CharacterController(feet: SIMD3(0, 1.5, 10), tuning: CharacterController.Tuning())
        var strides = 0
        for _ in 0..<120 {
            c.step(yaw: 0, input: MovementInput(forward: 1), deltaTime: step, in: slope)
            strides += c.events.filter { if case .stride = $0 { true } else { false } }.count
        }
        // Six metres at 2.6 m a stride, from a first step at 0.6: two or three — not one per bump.
        #expect(strides >= 2 && strides <= 3, "\(strides) footsteps walking six metres down a slope")
    }

    @Test("Feet alternate")
    func feetAlternate() {
        var c = CharacterController(feet: .zero)
        let feet = strides(&c, seconds: 3, MovementInput(forward: 1)).compactMap { event -> CharacterController.Foot? in
            if case .stride(let foot, _) = event { foot } else { nil }
        }
        #expect(feet.count > 4)
        #expect(zip(feet, feet.dropFirst()).allSatisfy { $0 != $1 })
    }

    /// A slide is a body skidding; footsteps under it would be feet that are not moving.
    @Test("A slide makes no footsteps")
    func slideIsSilent() {
        var c = CharacterController(feet: .zero)
        _ = strides(&c, seconds: 1, MovementInput(forward: 1, sprint: true))
        c.step(yaw: 0, input: MovementInput(forward: 1, sprint: true), crouching: true, deltaTime: step, in: flat)
        var during: [CharacterController.Event] = []
        while c.isSliding {
            c.step(yaw: 0, input: MovementInput(forward: 1, sprint: true), crouching: true,
                   deltaTime: step, in: flat)
            if c.isSliding { during += c.events }
        }
        #expect(strideCount(during) == 0)
    }

    @Test("A fall lands once, with the speed it hit at")
    func landing() {
        var c = CharacterController(feet: SIMD3(0, 1.8, 0))
        var landings: [Float] = []
        for _ in 0..<(120 * 2) {
            c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: flat)
            for case .landed(let speed) in c.events { landings.append(speed) }
        }
        #expect(landings.count == 1)
        // From rest through 1.8 m at 20 m/s²: √(2 · 20 · 1.8) ≈ 8.5 m/s.
        #expect(abs((landings.first ?? 0) - (2 * 20 * 1.8 as Float).squareRoot()) < 0.4)
    }

    /// Down a stair is not a landing — the body never left the ground.
    @Test("Stepping down a stair is not a landing")
    func stairIsNotALanding() {
        let platform = BoundingBox(minimum: SIMD3(-3, 0, -3), maximum: SIMD3(3, 0.3, 3))
        let world = CharacterController.Surroundings(solids: [platform])
        var c = CharacterController(feet: SIMD3(0, 0.3, 0))
        let events = strides(&c, seconds: 2, MovementInput(forward: 1), in: world)
        #expect(!events.contains { if case .landed = $0 { true } else { false } })
    }

    @Test("A jump is reported, and so is coming down from it")
    func jumpAndLand() {
        var c = CharacterController(feet: .zero)
        var events: [CharacterController.Event] = []
        c.step(yaw: 0, input: MovementInput(), jump: true, deltaTime: step, in: flat)
        events += c.events
        for _ in 0..<120 {
            c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: flat)
            events += c.events
        }
        #expect(events.first == .jumped)
        #expect(events.contains { if case .landed = $0 { true } else { false } })
    }

    /// What a footstep needs to sound like anything: which surface is underfoot.
    @Test("It knows which solid it is standing on, and when it is on the terrain")
    func knowsTheGround() {
        let slab = BoundingBox(minimum: SIMD3(-3, 0, -8), maximum: SIMD3(3, 0.3, -2))
        let world = CharacterController.Surroundings(solids: [ledge(height: 5, ahead: 30), slab])
        var c = CharacterController(feet: .zero)
        c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: world)
        #expect(c.groundSolid == nil)
        _ = strides(&c, seconds: 0.8, MovementInput(forward: 1), in: world)
        #expect(c.groundSolid == 1, "on the slab, which is solid 1")
        _ = strides(&c, seconds: 1.2, MovementInput(forward: 1), in: world)
        #expect(c.groundSolid == nil, "off the far end, back on the terrain")
    }

    @Test("Events are this step's only")
    func eventsClear() {
        var c = CharacterController(feet: SIMD3(0, 0.5, 0))
        var sawLanding = false
        for _ in 0..<120 {
            c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: flat)
            if c.events.contains(where: { if case .landed = $0 { true } else { false } }) { sawLanding = true; break }
        }
        #expect(sawLanding)
        c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: flat)
        #expect(c.events.isEmpty)
    }
}

// MARK: - The landing dip

@Suite("Character controller — the landing dip")
struct CharacterLandingDipTests {

    /// Drops from a height and records the compression every step from the landing on.
    private func drop(from height: Float) -> (curve: [Float], impact: Float, controller: CharacterController) {
        var c = CharacterController(feet: SIMD3(0, height, 0))
        var curve: [Float] = []
        var impact: Float = 0
        var landed = false
        for _ in 0..<(120 * 3) {
            c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: flat)
            for case .landed(let speed) in c.events { impact = speed; landed = true }
            if landed { curve.append(c.landingCompression) }
        }
        return (curve, impact, c)
    }

    @Test("A fall dips as far as its impact says, and no further")
    func depthFollowsImpact() {
        let result = drop(from: 1.8)
        let tuning = CharacterController.Tuning()
        let expected = (result.impact - tuning.landingSoftImpact)
            / (tuning.landingHardImpact - tuning.landingSoftImpact)
        let peak = result.curve.max() ?? 0
        #expect(abs(peak - expected) < expected * 0.12, "peaked at \(peak) against \(expected)")
    }

    /// **Down fast enough to be the impact, up slowly enough to be the legs.**
    @Test("It bottoms out quickly and recovers within half a second, without bouncing")
    func shape() {
        let curve = drop(from: 1.8).curve
        let peakStep = curve.firstIndex(of: curve.max() ?? 0) ?? 0
        let peakSeconds = Float(peakStep) * step
        #expect(peakSeconds > 0.04 && peakSeconds < 0.11, "lowest at \(peakSeconds) s")
        #expect(curve[Int(0.5 / step)] < 0.03, "still \(curve[Int(0.5 / step)]) compressed at 0.5 s")
        #expect(curve.allSatisfy { $0 >= 0 }, "the legs overshot and lifted the eye")
        // Critically damped: after the lowest point, it only ever comes back up.
        #expect(zip(curve[peakStep...], curve[(peakStep + 1)...]).allSatisfy { $0 >= $1 - 1e-6 })
    }

    @Test("A harder landing dips deeper, up to a limit")
    func harderIsDeeper() {
        let low = drop(from: 0.8).curve.max() ?? 0
        let high = drop(from: 2.5).curve.max() ?? 0
        let extreme = drop(from: 30).curve.max() ?? 0
        #expect(high > low)
        #expect(extreme < 1.12, "the hardest landing compressed \(extreme)")
    }

    /// A fall shorter than a step is a step down, not a landing, so the soft case is a small hop.
    @Test("A landing too soft to feel does not dip")
    func softIsFlat() {
        var tuning = CharacterController.Tuning()
        tuning.jumpSpeed = 2.5                       // lands at 2.5 m/s, under the soft threshold
        var c = CharacterController(feet: .zero, tuning: tuning)
        var landed = false
        c.step(yaw: 0, input: MovementInput(), jump: true, deltaTime: step, in: flat)
        for _ in 0..<120 {
            c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: flat)
            if c.events.contains(where: { if case .landed = $0 { true } else { false } }) { landed = true }
            #expect(c.landingCompression == 0)
        }
        #expect(landed)
    }

    /// The exact step lands on the same curve however long the step is.
    @Test("The dip is the same at 60 Hz and 240 Hz")
    func stepSizeIndependent() {
        func peak(hz: Float) -> Float {
            let dt = 1 / hz
            var c = CharacterController(feet: SIMD3(0, 1.8, 0))
            var deepest: Float = 0
            for _ in 0..<Int(hz * 2) {
                c.step(yaw: 0, input: MovementInput(), deltaTime: dt, in: flat)
                deepest = max(deepest, c.landingCompression)
            }
            return deepest
        }
        // Not identical — the landing speed itself depends on where the step boundaries fall.
        #expect(abs(peak(hz: 60) - peak(hz: 240)) < 0.06, "\(peak(hz: 60)) against \(peak(hz: 240))")
    }

    /// The legs take the weight — the eye really is lower — while the feet stay on the ground.
    @Test("The eye drops and the feet do not")
    func eyeNotFeet() {
        var c = CharacterController(feet: SIMD3(0, 1.8, 0))
        var deepest: Float = 0
        for _ in 0..<(120 * 2) {
            c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: flat)
            if c.isGrounded {
                #expect(c.feet.y == 0)
                deepest = max(deepest, c.tuning.eyeHeight - (c.eye.y - c.feet.y))
            }
        }
        #expect(deepest > 0.05, "the eye dropped only \(deepest) m")
        #expect(abs(deepest - (drop(from: 1.8).curve.max() ?? 0) * c.tuning.landingDropMax) < 0.01)
    }

    @Test("The view tips down with the drop, and comes back")
    func viewTips() {
        var c = CharacterController(feet: SIMD3(0, 1.8, 0))
        var lowest: Float = 0
        for _ in 0..<(120 * 2) {
            c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: flat)
            lowest = min(lowest, c.landingCameraDip)
        }
        #expect(lowest < -0.02)
        #expect(abs(c.landingCameraDip) < 1e-3)
    }

    @Test("Stepping down a stair does not dip")
    func stairsDoNotDip() {
        let platform = BoundingBox(minimum: SIMD3(-3, 0, -3), maximum: SIMD3(3, 0.3, 3))
        var c = CharacterController(feet: SIMD3(0, 0.3, 0))
        for _ in 0..<(120 * 2) {
            c.step(yaw: 0, input: MovementInput(forward: 1), deltaTime: step,
                   in: CharacterController.Surroundings(solids: [platform]))
            #expect(c.landingCompression == 0)
        }
    }
}

// MARK: - Head bob

@Suite("Character controller — head bob")
struct CharacterHeadBobTests {

    /// Steps the body and hands back each step's bob, and whether a foot came down on it.
    private func samples(_ c: inout CharacterController, seconds: Float, _ input: MovementInput,
                         jump: Bool = false, crouching: Bool = false,
                         in world: CharacterController.Surroundings = flat) -> [(bob: SIMD2<Float>, footfall: Bool)] {
        var out: [(SIMD2<Float>, Bool)] = []
        for _ in 0..<Int((seconds / step).rounded()) {
            c.step(yaw: 0, input: input, jump: jump, crouching: crouching, deltaTime: step, in: world)
            out.append((c.headBob, c.events.contains { if case .stride = $0 { true } else { false } }))
        }
        return out
    }

    private func span(_ values: [Float]) -> Float { (values.max() ?? 0) - (values.min() ?? 0) }

    private func settled(_ input: MovementInput, crouching: Bool = false) -> [(bob: SIMD2<Float>, footfall: Bool)] {
        var c = CharacterController(feet: .zero)
        _ = samples(&c, seconds: 1.5, input, crouching: crouching)
        return samples(&c, seconds: 2, input, crouching: crouching)
    }

    @Test("Standing still does not bob")
    func stillIsStill() {
        var c = CharacterController(feet: .zero)
        let bobs = samples(&c, seconds: 1, MovementInput())
        #expect(bobs.allSatisfy { $0.bob == .zero })
    }

    @Test("A walk bobs by the tuned amounts, up and down and side to side")
    func walkAmplitude() {
        let t = CharacterController.Tuning()
        let bobs = settled(MovementInput(forward: 1))
        let rise = span(bobs.map(\.bob.y)), sway = span(bobs.map(\.bob.x))
        #expect(abs(rise - 2 * t.bobRise) < 0.1 * 2 * t.bobRise, "rise \(rise)")
        #expect(abs(sway - 2 * t.bobSway) < 0.1 * 2 * t.bobSway, "sway \(sway)")
    }

    /// **The head is lowest as the foot lands** — which is what ties the bob to the footsteps a
    /// player hears. A bob out of phase with them reads as the camera wobbling on its own.
    @Test("The head is at its lowest as each foot comes down")
    func lowestAtFootfall() {
        let t = CharacterController.Tuning()
        let footfalls = settled(MovementInput(forward: 1)).filter(\.footfall)
        #expect(footfalls.count >= 3)
        for f in footfalls { #expect(f.bob.y < -0.9 * t.bobRise, "a foot landed with the head at \(f.bob.y)") }
    }

    /// Two dips for every sway: the sway leans one way for a step and the other way for the next.
    @Test("The sway changes side with every step: a figure-eight, not a loop")
    func swayAlternates() {
        let bobs = settled(MovementInput(forward: 1))
        var sides: [Float] = []
        var widest: Float = 0
        for sample in bobs {
            if sample.footfall {
                if widest != 0 { sides.append(widest) }
                widest = 0
            } else if abs(sample.bob.x) > abs(widest) {
                widest = sample.bob.x
            }
        }
        #expect(sides.count >= 3)
        for (a, b) in zip(sides, sides.dropFirst()) { #expect(a * b < 0, "two steps leaned the same way: \(sides)") }
    }

    @Test("A sprint bobs more than a walk, and a crouch less")
    func gaitScales() {
        let t = CharacterController.Tuning()
        let walk = span(settled(MovementInput(forward: 1)).map(\.bob.y))
        let sprint = span(settled(MovementInput(forward: 1, sprint: true)).map(\.bob.y))
        let crouch = span(settled(MovementInput(forward: 1), crouching: true).map(\.bob.y))
        #expect(abs(sprint / walk - t.bobSprintScale) < 0.1, "sprint \(sprint) against walk \(walk)")
        #expect(abs(crouch / walk - t.bobCrouchScale) < 0.1, "crouch \(crouch) against walk \(walk)")
    }

    /// **Eased out, not switched off** — stopping mid-stride must not park the view off centre and
    /// then snap it back.
    @Test("Stopping lets the bob die away smoothly")
    func stopsSmoothly() {
        var c = CharacterController(feet: .zero)
        _ = samples(&c, seconds: 2, MovementInput(forward: 1))
        var last = c.headBob, biggestJump: Float = 0
        for sample in samples(&c, seconds: 0.8, MovementInput()) {
            biggestJump = max(biggestJump, simd_length(sample.bob - last))
            last = sample.bob
        }
        #expect(simd_length(c.headBob) < 0.001, "still bobbing \(c.headBob) after stopping")
        #expect(biggestJump < 0.002, "the bob jumped \(biggestJump) m in one step")
    }

    @Test("Pushing into a wall does not bob")
    func wallDoesNotBob() {
        var c = CharacterController(feet: .zero)
        let wall = BoundingBox(minimum: SIMD3(-3, 0, -2), maximum: SIMD3(3, 3, -1))
        let world = CharacterController.Surroundings(solids: [wall])
        _ = samples(&c, seconds: 1.5, MovementInput(forward: 1), in: world)
        let bobs = samples(&c, seconds: 1, MovementInput(forward: 1), in: world)
        #expect(bobs.allSatisfy { simd_length($0.bob) < 0.0005 })
    }

    /// Neither the air nor a slide has footfalls, so neither has a bob.
    @Test("No bob in the air or in a slide")
    func airAndSlide() {
        let t = CharacterController.Tuning()
        var c = CharacterController(feet: .zero)
        _ = samples(&c, seconds: 1.5, MovementInput(forward: 1))
        let flight = samples(&c, seconds: 0.5, MovementInput(forward: 1), jump: true)
        #expect(simd_length(flight.last!.bob) < 0.1 * t.bobRise, "bobbing in mid-air: \(flight.last!.bob)")

        var s = CharacterController(feet: .zero)
        _ = samples(&s, seconds: 1.5, MovementInput(forward: 1, sprint: true))
        let slide = samples(&s, seconds: 0.6, MovementInput(forward: 1, sprint: true), crouching: true)
        #expect(s.isSliding)
        #expect(simd_length(slide.last!.bob) < 0.1 * t.bobRise, "bobbing through a slide: \(slide.last!.bob)")
    }

    /// **The case that needed ``CharacterController/headBob``'s catch-up.** A step up jumps the stride
    /// phase to a footfall, and a bob read straight off the phase jumped with it — every tread.
    @Test("Climbing stairs does not jolt the bob")
    func stairsDoNotJolt() {
        var treads: [BoundingBox] = []
        for i in 0..<4 {
            let near = -Float(i + 1), far = -Float(i + 2), top = 0.3 * Float(i + 1)
            treads.append(BoundingBox(minimum: SIMD3<Float>(-3, 0, far), maximum: SIMD3<Float>(3, top, near)))
        }
        let landing = BoundingBox(minimum: SIMD3(-3, 0, -12), maximum: SIMD3(3, 1.2, -5))
        let world = CharacterController.Surroundings(solids: treads + [landing])
        var c = CharacterController(feet: SIMD3(0, 0, 6))
        _ = samples(&c, seconds: 1.2, MovementInput(forward: 1), in: flat)   // up to speed on the flat
        var last = c.headBob, biggestJump: Float = 0
        for sample in samples(&c, seconds: 1.5, MovementInput(forward: 1), in: world) {
            biggestJump = max(biggestJump, simd_length(sample.bob - last))
            last = sample.bob
        }
        #expect(abs(c.feet.y - 1.2) < 1e-4, "did not climb the stairs")
        #expect(biggestJump < 0.004, "the bob jumped \(biggestJump) m in one step on the stairs")
    }
}

// MARK: - Room to stand

@Suite("Character controller — room to stand")
struct CharacterHeadroomTests {

    /// A beam across the path, its underside at 1.5 m: a crouched body (1.2 m) goes under it, a
    /// standing one (1.85 m) does not.
    private let world = CharacterController.Surroundings(solids: [
        BoundingBox(minimum: SIMD3(-3, 1.5, -4.5), maximum: SIMD3(3, 2.5, -3.5)),
    ])

    /// Crouches, and walks until the feet are under the middle of the beam.
    private func underTheBeam() -> CharacterController {
        var c = CharacterController(feet: .zero)
        run(&c, seconds: 1, crouching: true, in: world)
        while c.feet.z > -4 {
            c.step(yaw: 0, input: MovementInput(forward: 1), crouching: true, deltaTime: step, in: world)
        }
        return c
    }

    /// **The bug**: the body rose into the beam, 35 cm of head inside the stone, and every move after
    /// that was refused because the body already overlapped the beam. Stuck until crouching again.
    @Test("Letting go of crouch under a beam keeps the body down")
    func staysDownUnderABeam() {
        var c = underTheBeam()
        run(&c, seconds: 1, crouching: false, in: world)
        #expect(c.isHeldDown)
        #expect(abs(c.eye.y - c.tuning.crouchedEyeHeight) < 1e-4, "stood to \(c.eye.y) under a 1.5 m beam")
        #expect(c.bounds.maximum.y < 1.5, "the head is inside the beam: \(c.bounds.maximum.y)")
    }

    @Test("Walking out from under it stands up, at once and on its own")
    func standsWhenClear() {
        var c = underTheBeam()
        run(&c, seconds: 0.5, crouching: false, in: world)
        var stoodAt: Float?
        for _ in 0..<240 {
            c.step(yaw: 0, input: MovementInput(forward: 1), crouching: false, deltaTime: step, in: world)
            if stoodAt == nil && c.eye.y > c.tuning.crouchedEyeHeight + 0.01 { stoodAt = c.feet.z }
        }
        #expect(!c.isHeldDown)
        #expect(abs(c.eye.y - c.tuning.eyeHeight) < 1e-4, "never stood: \(c.eye.y)")
        // The beam ends at z = −4.5 and the body is 0.3 either side of its feet.
        #expect(stoodAt.map { $0 < -4.8 && $0 > -5.0 } == true, "began to stand at z \(stoodAt ?? .nan)")
    }

    /// Held down is crouched in every respect: a crouched walk's speed, and no sprint.
    @Test("Held down under a beam, the walk is a crouched walk and cannot sprint")
    func heldDownIsCrouched() {
        var c = underTheBeam()
        run(&c, seconds: 0.5, crouching: false, in: world)
        let before = c.feet
        c.step(yaw: .pi / 2, input: MovementInput(forward: 1, sprint: true), crouching: false, deltaTime: step, in: world)
        let speed = simd_distance(ground(before), ground(c.feet)) / step
        let crouchedSpeed = c.tuning.walkSpeed * c.tuning.crouchedSpeedFraction
        #expect(abs(speed - crouchedSpeed) < 0.01, "moved at \(speed) m/s under the beam, sprint held")
    }

    /// **Found by the sample**: the walk stops a body against a face to within the collision
    /// tolerance, and the first headroom check counted that touch as the beam being overhead — a
    /// player who only walked up to a low beam was pushed into a crouch.
    @Test("Walking up to a low beam standing stops at it, still standing")
    func walkingUpToABeamStaysStanding() {
        var c = CharacterController(feet: SIMD3(0, 0, 6))
        run(&c, seconds: 2, MovementInput(forward: 1), in: world)
        #expect(abs(c.feet.z + 3.2) < 0.01, "should stop at the beam's face: \(c.feet.z)")
        #expect(!c.isHeldDown)
        #expect(abs(c.eye.y - c.tuning.eyeHeight) < 1e-4, "walked into a crouch: eye \(c.eye.y)")
    }

    @Test("In the open, letting go of crouch stands as it always did")
    func openAirUnchanged() {
        var c = CharacterController(feet: .zero)
        run(&c, seconds: 1, crouching: true, in: world)
        run(&c, seconds: 1, crouching: false, in: world)
        #expect(!c.isHeldDown && abs(c.eye.y - c.tuning.eyeHeight) < 1e-4)
    }
}

// MARK: - Something that moves

@Suite("Character controller — standing on something that moves")
struct CharacterPlatformTests {

    /// A 3 m square slab, its top at `top`, centred at `centre` on the ground plane.
    private func slab(top: Float, centre: SIMD2<Float> = .zero) -> BoundingBox {
        BoundingBox(minimum: SIMD3(centre.x - 1.5, top - 0.5, centre.y - 1.5),
                    maximum: SIMD3(centre.x + 1.5, top, centre.y + 1.5))
    }

    /// Steps a body on a slab that moves by `velocity` each second, with `others` still around it.
    /// Returns the slab's final top and centre.
    @discardableResult
    private func ride(_ c: inout CharacterController, from top: Float, centre: SIMD2<Float> = .zero,
                      velocity: SIMD3<Float>, seconds: Float, _ input: MovementInput = MovementInput(),
                      others: [BoundingBox] = []) -> (top: Float, centre: SIMD2<Float>) {
        var top = top, centre = centre
        for _ in 0..<Int((seconds / step).rounded()) {
            let delta = velocity * step
            top += delta.y
            centre += SIMD2(delta.x, delta.z)
            var world = CharacterController.Surroundings(solids: [slab(top: top, centre: centre)] + others)
            world.motion = [delta]
            c.step(yaw: 0, input: input, deltaTime: step, in: world)
        }
        return (top, centre)
    }

    private func standing(on top: Float) -> CharacterController {
        var c = CharacterController(feet: SIMD3(0, top, 0))
        let still = CharacterController.Surroundings(solids: [slab(top: top)])
        for _ in 0..<60 { c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: still) }
        return c
    }

    @Test("A lift going up carries the body up with it, exactly")
    func carriedUp() {
        var c = standing(on: 0.3)
        let end = ride(&c, from: 0.3, velocity: SIMD3(0, 1.2, 0), seconds: 1)
        #expect(abs(c.feet.y - end.top) < 1e-4, "feet at \(c.feet.y), lift top at \(end.top)")
        #expect(c.isGrounded && c.groundSolid == 0)
        #expect(abs(c.eye.y - c.feet.y - c.tuning.eyeHeight) < 1e-4, "the eye should ride rigidly, not ease after it")
    }

    /// Faster than gravity would drop you: without the carry the body would fall behind and land.
    @Test("A lift going down keeps the body on it — no fall, no landing")
    func carriedDown() {
        var c = standing(on: 12)
        var landings = 0
        var top: Float = 12
        for _ in 0..<120 {
            let delta = SIMD3<Float>(0, -9, 0) * step
            top += delta.y
            var world = CharacterController.Surroundings(solids: [slab(top: top)])
            world.motion = [delta]
            c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: world)
            landings += c.events.filter { if case .landed = $0 { true } else { false } }.count
            #expect(c.isGrounded)
        }
        #expect(abs(c.feet.y - top) < 1e-4 && landings == 0, "feet \(c.feet.y), top \(top), \(landings) landings")
    }

    @Test("Riding without walking makes no footsteps and no bob")
    func ridingIsNotWalking() {
        var c = standing(on: 0.3)
        var strides = 0
        var top: Float = 0.3, centre = SIMD2<Float>(0, 0)
        for _ in 0..<240 {
            let delta = SIMD3<Float>(2, 0.5, 0) * step
            top += delta.y
            centre += SIMD2(delta.x, delta.z)
            var world = CharacterController.Surroundings(solids: [slab(top: top, centre: centre)])
            world.motion = [delta]
            c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: world)
            strides += c.events.filter { if case .stride = $0 { true } else { false } }.count
        }
        #expect(strides == 0 && c.headBob == .zero, "\(strides) footsteps riding a platform standing still")
        #expect(abs(c.feet.x - centre.x) < 1e-3, "carried across with it")
    }

    @Test("Walking on a moving platform is walking relative to it")
    func walkingRelative() {
        var c = standing(on: 0.3)
        // The platform slides +x at 1 m/s; the body walks −z at 6 m/s for a quarter second.
        let end = ride(&c, from: 0.3, velocity: SIMD3(1, 0, 0), seconds: 0.25, MovementInput(forward: 1))
        #expect(abs(c.feet.x - end.centre.x) < 1e-3, "kept the platform's sideways motion")
        #expect(abs(c.feet.z + 1.5) < 0.01, "walked its own 1.5 m on top of it: z \(c.feet.z)")
    }

    /// **The carry goes through collision**: a platform sliding under a wall does not take the body
    /// through it. The body stays at the wall until the platform leaves it behind.
    @Test("A platform does not carry the body through a wall")
    func notThroughWalls() {
        var c = standing(on: 0.3)
        let wall = BoundingBox(minimum: SIMD3(1, 0.3, -3), maximum: SIMD3(1.2, 3, 3))   // stands on the slab
        ride(&c, from: 0.3, velocity: SIMD3(2, 0, 0), seconds: 0.5, others: [wall])
        #expect(c.feet.x <= 1 - c.tuning.radius + 1e-3, "carried into the wall: x \(c.feet.x)")
        #expect(c.carried.x < 1e-6, "the carry should read as stopped at the wall: \(c.carried)")
    }

    @Test("Off the platform, nothing carries")
    func offIsOff() {
        var c = CharacterController(feet: SIMD3(5, 0, 0))
        var world = CharacterController.Surroundings(solids: [slab(top: 1)])
        world.motion = [SIMD3(0, 0.5, 0)]
        for _ in 0..<30 { c.step(yaw: 0, input: MovementInput(), deltaTime: step, in: world) }
        #expect(c.feet == SIMD3(5, 0, 0) && c.carried == .zero)
    }
}
