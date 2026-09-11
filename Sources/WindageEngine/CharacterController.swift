//
//  CharacterController.swift
//  WindageEngine
//

import simd

/// A body with feet: walking across the ground, standing on things, stepping up, falling off, and
/// crouching.
///
/// ### Extracted, then finished
///
/// **The walking half is not new.** A game built on this engine has shipped it for a while: movement
/// along the ground plane rather than the look direction, a crouch that is a posture with a cost, a
/// slide that carries a sprint's momentum into it, and an eye that settles onto rough ground rather
/// than jittering over it. Every number here that describes *how walking feels* came across with it,
/// tuned in play, and the reasons came with them.
///
/// **What it did not have is anything to stand on but a height function.** Its world was one
/// terrain with nothing on it, so it had no gravity ("there is nothing to fall off"), no step height
/// and no obstacles. A second consumer with crates, ledges and a plinth is what showed where the
/// seam was: the ground is not a function of the game's, it is a question the controller asks —
/// see ``Surroundings``.
///
/// ### The body is a box, and that is a choice
///
/// A capsule is the textbook body, because it slides round corners and up slopes on its own. Against
/// a world made of axis-aligned boxes — which is what `Volume.worldBounds` produces, and what every
/// solid in a level currently is — a box body is **exact**: two ranges per axis, no contact normals,
/// no penetration depth to resolve. The cost is that it catches on a corner where a capsule would
/// glance off, and the axis-at-a-time move below is what takes most of that back.
///
/// ### Vertical movement is smoothed; the body is not
///
/// Every time the ground under a grounded player changes height — a step up, a step down, the next
/// bump of a noisy terrain — the *feet* move there at once, because collision has to be exact. The
/// *eye* takes a moment to follow (``Tuning/settleRate``). That is the whole of what makes stairs
/// read as stairs rather than as a stutter, and it is what the extracted code did for terrain; here
/// it covers ledges too. A fall is never smoothed — a landing is felt, not eased.
public nonisolated struct CharacterController: Sendable {

    // MARK: - The world, as the controller sees it

    /// Where the controller can stand and what it cannot walk through.
    ///
    /// **Two kinds of thing, because they behave differently.** Terrain is a floor that is always
    /// there and never in the way: you cannot go below it, and walking into a rise in it means
    /// walking up it. A solid is a box: it can be stood on, it can be stepped onto if it is low
    /// enough, and otherwise it stops you.
    public struct Surroundings: Sendable {
        /// Terrain height at a world x/z. A flat world returns a constant.
        public var groundHeight: @Sendable (Float, Float) -> Float
        /// Every box that can be stood on or walked into, in world space.
        public var solids: [BoundingBox]

        public init(groundHeight: @escaping @Sendable (Float, Float) -> Float = { _, _ in 0 },
                    solids: [BoundingBox] = []) {
            self.groundHeight = groundHeight
            self.solids = solids
        }
    }

    // MARK: - Tuning

    /// How walking feels. **A game's numbers, with the defaults it was tuned with.**
    ///
    /// The walking and posture values arrived tuned from play, and each carries its reason. The
    /// body, step, gravity and jump values are new and are ordinary first-person numbers; a game
    /// with a different scale or feel changes them here rather than in the controller.
    public struct Tuning: Sendable, Equatable {

        /// Metres per second.
        public var walkSpeed: Float = Camera.walkSpeed
        public var sprintSpeed: Float = Camera.sprintSpeed

        /// Eye height standing, in metres above the feet.
        public var eyeHeight: Float = 1.7

        /// Eye height crouched.
        ///
        /// **Crouch is a posture, not an upgrade.** A posture that is only better is not a choice,
        /// it is a thing you hold down forever — so it costs speed and the sprint.
        public var crouchedEyeHeight: Float = 1.05

        /// How much of a walk you manage crouched.
        public var crouchedSpeedFraction: Float = 0.45

        /// How fast the eye moves between postures, in metres per second. Fast enough to feel
        /// responsive, slow enough that the view does not teleport.
        public var postureRate: Float = 2.2

        /// How long a slide runs before it has bled down to a crouched walk, in seconds.
        ///
        /// **Crouching mid-sprint carries your momentum rather than deleting it** — standing still the
        /// instant you crouch is the one thing a runner's body does not do. It is not movement tech:
        /// no chaining, no jump out of it, and about twelve metres long.
        public var slideSeconds: Float = 1.15

        /// The exponent applied to the fraction of a slide remaining. **Below 1 holds the speed and
        /// lets go late**, which is what a slide is; above 1 dumps it at once and leaves a crouch
        /// with a flourish. It was tuned *down* twice in play, from 2 and then 0.5.
        public var slideEasing: Float = 0.35

        /// How far the view tips forward at the start of a slide, in radians — about 7°.
        public var slideDipRadians: Float = 0.12

        /// How much of the player's steering still reaches a slide, 0…1.
        ///
        /// **What separates a slide from running while crouched.** With full steering the player is
        /// still driving; a slide is committed — you go where you were already going.
        public var slideSteering: Float = 0.15

        /// How much faster the eye drops during a slide, as a multiple of ``postureRate``. Going
        /// down is the part of a slide you feel, and it arrives before the speed can tell you
        /// anything.
        public var slideDropRate: Float = 7

        /// How fast the eye catches up with a change in the height of the ground under it, as a
        /// fraction closed per second. See the type's notes on smoothing.
        public var settleRate: Float = 12

        /// Half the width of the body's footprint, in metres.
        public var radius: Float = 0.3

        /// How far the top of the body is above the eye. The body is `eye height + this` tall.
        public var headroom: Float = 0.15

        /// The tallest ledge walked onto without a jump.
        ///
        /// **Tall enough for a stair, a kerb and a low plinth; short enough that a crate stops you.**
        /// A crate that could be walked onto is a crate that is not cover.
        public var stepHeight: Float = 0.45

        /// Metres per second squared.
        ///
        /// **About twice real gravity, which is what games use.** At 9.8 a fall reads as floating —
        /// a first-person camera has no body in view to give the drop a scale, so the eye judges it
        /// against expectation, and expectation is set by games.
        public var gravity: Float = 20

        /// Upward speed at the moment of a jump, in metres per second. With the default gravity this
        /// clears about a metre: onto a low wall, not onto a crate.
        public var jumpSpeed: Float = 6.3

        /// How long after walking off an edge a jump still counts, in seconds.
        ///
        /// **Without it, a jump pressed on the last frame of a ledge does nothing**, because the
        /// player has technically already left it — which reads as the game eating the input.
        public var coyoteSeconds: Float = 0.1

        /// How long a jump pressed *before* landing is remembered, in seconds. The same problem from
        /// the other side: pressing jump a moment before touching down should jump on touchdown.
        public var jumpBufferSeconds: Float = 0.12

        /// Metres between footfalls at a walk, at a sprint, and crouched.
        ///
        /// **Longer than a person's, because these speeds are faster than a person's.** A walk here
        /// is six metres a second — a jog — and a footstep every real 0.7 m would be eight a second,
        /// which reads as a drum roll. These give about 2.3 steps a second walking, 3.6 sprinting and
        /// 1.7 crouched: a cadence the ear accepts as feet, whatever the distance says.
        public var walkStride: Float = 2.6
        public var sprintStride: Float = 5.0
        public var crouchStride: Float = 1.6

        /// How far through a stride the first one starts, when setting off from standing.
        ///
        /// **Not zero**, or the first footstep arrives a whole stride after the key goes down and the
        /// start of a walk is silent; not one, or tapping a key makes a sound for a movement too small
        /// to have taken a step.
        public var firstStepPhase: Float = 0.6

        /// How far the eye drops, in metres, and how far the view tips down, in radians, on the
        /// hardest landing — scaled down for softer ones.
        ///
        /// **Both, because they say different things.** The drop is the legs taking the weight: the
        /// eye really is lower for a moment, and it moves with the body. The tip is the head nodding
        /// with it, and like the slide's it is for the **view only** — see ``landingCameraDip``. A
        /// drop alone reads as the floor sinking; a tip alone reads as the camera being nudged.
        public var landingDropMax: Float = 0.16
        public var landingDipMax: Float = 0.06

        /// Landing speeds, metres per second, below which there is no dip and above which it is full.
        ///
        /// **A jump's own landing is 6.3 m/s**, so it dips about a third: enough to feel the ground
        /// arrive, not enough to make hopping about a camera shake. The hardest, 12, is a fall of 3.6 m.
        public var landingSoftImpact: Float = 3
        public var landingHardImpact: Float = 12

        /// How quickly the knees give and recover, radians per second — a critically damped spring.
        /// At 14 the eye is at its lowest 70 ms after touching down and back within about 0.4 s:
        /// **down fast enough to be the impact, up slowly enough to be the legs.** Critically damped so
        /// it never overshoots, which would read as a bounce.
        public var landingSpring: Float = 14

        /// How far the head rises and falls, and sways side to side, at a walk — metres, each an
        /// amplitude either side of still.
        ///
        /// **Up and down twice for every side to side.** The head is lowest as each foot comes down
        /// and sways toward whichever leg is carrying it, so the vertical runs at every footfall and
        /// the sway at every other one: a figure-eight. The vertical is the larger — it is the one
        /// that reads as a walk — and the sway smaller, or the pair traces a loop and reads as
        /// swimming. **Small on purpose**: bob is the effect most often overdone, and a known cause
        /// of motion sickness; these are about half a real head's excursion.
        public var bobRise: Float = 0.014
        public var bobSway: Float = 0.009

        /// The bob at a sprint and crouched, as multiples of the walk's.
        public var bobSprintScale: Float = 1.7
        public var bobCrouchScale: Float = 0.5

        /// How fast the bob comes and goes, as a fraction per second — setting off, stopping,
        /// leaving the ground. **Eased, never switched**: a bob that stops dead mid-stride leaves the
        /// view parked a centimetre off where it rests, and then snaps it back.
        public var bobEase: Float = 8

        public init() {}

        /// Metres per footfall at a speed.
        func strideLength(atSpeed speed: Float, crouching: Bool) -> Float {
            if crouching { return crouchStride }
            let t = simd_clamp((speed - walkSpeed) / max(sprintSpeed - walkSpeed, 1e-3), 0, 1)
            return walkStride + (sprintStride - walkStride) * t
        }

        /// The body's height for a posture height.
        func bodyHeight(for eye: Float) -> Float { eye + headroom }
    }

    public var tuning: Tuning

    // MARK: - State

    /// Where the feet are. **Exact** — collision is resolved against this, never against the eye.
    public private(set) var feet: SIMD3<Float>

    /// Metres per second, positive up.
    public private(set) var verticalVelocity: Float = 0

    /// Whether the feet are on something.
    public private(set) var isGrounded = true

    /// Metres from the feet to the eye for the current posture, between the crouched and standing
    /// heights. **Carried rather than inferred from the eye**, because the eye also moves for
    /// reasons that are not posture — the ground changing under it — and deriving one from the other
    /// makes a walk downhill look like standing up.
    public private(set) var height: Float

    /// The part of a recent change in ground height the eye has not caught up with yet.
    private var settling: Float = 0

    /// The direction a slide was entered in, held for its duration.
    public private(set) var slideDirection = SIMD2<Float>(0, -1)
    /// Seconds left of a slide. Zero when not sliding.
    public private(set) var slideLeft: Float = 0
    /// Which way the last step actually moved. **This is what a slide inherits.**
    private var lastDirection = SIMD2<Float>(0, -1)
    /// Last step's inputs, so a slide or a jump starts on an edge rather than while a key is merely
    /// held. Without the edge, holding crouch through a sprint restarts the slide every step.
    private var wasCrouching = false
    private var wasSprinting = false
    private var wasJumpHeld = false
    private var coyoteLeft: Float = 0
    private var jumpBufferLeft: Float = 0

    // MARK: - What happened this step

    /// Which foot. Alternates, so a game can pan a footstep a little left or right.
    public enum Foot: Sendable, Equatable { case left, right }

    /// Something the body did that a game will want to hear, see or count.
    public enum Event: Sendable, Equatable {
        /// A foot came down. `speed` is the ground speed that step was taken at, metres per second.
        case stride(foot: Foot, speed: Float)
        /// Down from a fall or a jump. `impactSpeed` is how fast, metres per second, downward.
        case landed(impactSpeed: Float)
        /// Left the ground on purpose.
        case jumped
    }

    /// This step's events, in the order they happened. **Cleared at the start of every step**, so a
    /// game reads them after ``step(yaw:input:jump:crouching:deltaTime:in:)`` and before the next.
    public private(set) var events: [Event] = []

    /// Which of the ``Surroundings/solids`` the feet are on, or nil for the terrain or the air.
    ///
    /// **What a footstep needs to know to sound like anything** — stone steps and dirt are different
    /// sounds — and what a moving platform needs to know to carry you, when there is one.
    public private(set) var groundSolid: Int?

    /// How far through the current stride, 0…1.
    private var stridePhase: Float = 0
    private var nextFoot: Foot = .left
    private var wasMoving = false

    public init(feet: SIMD3<Float>, tuning: Tuning = Tuning()) {
        self.tuning = tuning
        self.feet = feet
        self.height = tuning.eyeHeight
    }

    /// Where the eye is: the feet, the posture, and whatever the eye has not yet settled.
    public var eye: SIMD3<Float> { feet + SIMD3(0, height + settling - landingDrop, 0) }

    /// The body's box at the feet's current position.
    public var bounds: BoundingBox { body(at: feet, eyeHeight: height) }

    public var isSliding: Bool { slideLeft > 0 }

    /// How far through a slide, 0 at entry to 1 at the end. Zero when not sliding.
    public var slideProgress: Float { slideLeft > 0 ? 1 - slideLeft / tuning.slideSeconds : 0 }

    /// A pitch kick for the *displayed* camera, in radians — nose down going in, recovering as the
    /// slide bleeds out. **Applied to the view, never to the aim**: folding it into the camera's own
    /// pitch would leave the player looking somewhere new every time they slid.
    public var slideCameraDip: Float {
        guard slideLeft > 0 else { return 0 }
        let t = slideProgress
        return -tuning.slideDipRadians * (1 - t) * (1 - t) * (1 + 3 * t)
    }

    /// How compressed the legs are from the last landing, 0 (standing) to about 1 (the hardest).
    public private(set) var landingCompression: Float = 0
    private var compressionRate: Float = 0

    /// How far the eye is below where it would stand, in metres, from the last landing. Part of
    /// ``eye`` — the body really is lower.
    public var landingDrop: Float { landingCompression * tuning.landingDropMax }

    /// A pitch kick for the *displayed* camera from the last landing, in radians, nose down. **Applied
    /// to the view, never to the aim**, by the same rule as ``slideCameraDip``: a player who fired on
    /// landing would otherwise shoot the ground.
    public var landingCameraDip: Float { -landingCompression * tuning.landingDipMax }

    /// The head's bob for the *displayed* camera, in metres: `x` to the right of the view, `y` up.
    ///
    /// **Locked to the stride, not to a clock.** It advances with the distance the feet actually
    /// cover — the same phase that sounds the footsteps — so the head dips as each foot lands, stops
    /// when the body stops, and marches on the spot for nobody pushing into a wall. A bob on a timer
    /// sways while standing still, which reads as swimming.
    ///
    /// **Applied to the view, never to the aim**, by the rule the dips follow: a bob in the aim is a
    /// crosshair that wanders while walking. Multiply it by the player's setting — see
    /// ``PlayerSettings/headBob`` — because some players cannot play with it at all.
    public var headBob: SIMD2<Float> { rawBob + bobCatchUp }

    /// How much bob there is, 0 to the sprint's scale — eased toward what the gait asks for.
    private var bobAmount: Float = 0
    /// What the bob has not caught up with yet, after the stride phase jumped. See ``footOnRise(_:)``.
    private var bobCatchUp = SIMD2<Float>.zero

    /// The bob the stride phase and the current amount give, before any catching up.
    private var rawBob: SIMD2<Float> {
        guard bobAmount > 0 else { return .zero }
        // Lowest as the foot lands (phase 0 and 1), highest between. Centred on zero, so walking
        // does not lower the eye on average.
        let rise = -tuning.bobRise * cos(2 * .pi * stridePhase)
        // Toward the leg carrying the body: the one *not* about to land, peaking mid-step and
        // crossing zero as each foot comes down — so it swings once for every two dips.
        let side: Float = nextFoot == .left ? 1 : -1
        let sway = tuning.bobSway * sin(.pi * stridePhase) * side
        return SIMD2(sway, rise) * bobAmount
    }

    // MARK: - One step

    /// Advances by one simulation step.
    ///
    /// - Parameters:
    ///   - yaw: which way the player faces. **Pitch does not appear**, and that is a guarantee:
    ///     walking moves along the ground plane, so looking at your feet does not slow you and
    ///     looking at the sky does not lift you.
    ///   - jump: whether jump is held. The press is found here, from the edge.
    ///   - crouching: the posture the player has chosen — a latch, in `InputState`.
    public mutating func step(yaw: Float,
                              input: MovementInput,
                              jump: Bool = false,
                              crouching: Bool = false,
                              deltaTime: Float,
                              in world: Surroundings) {
        let dt = max(deltaTime, 0)
        events.removeAll(keepingCapacity: true)

        // --- Slide: started on the *edge* of crouching, at sprint speed, while actually moving.
        let moving = input.forward != 0 || input.strafe != 0
        if crouching && !wasCrouching && wasSprinting && moving && isGrounded {
            slideLeft = tuning.slideSeconds
            // **The direction you were already going, not the one you are asking for.** Taking this
            // step's input launches the slide sideways if `C` lands mid-turn — that is teleporting,
            // not momentum.
            slideDirection = lastDirection
        }
        if !crouching || !moving { slideLeft = 0 }
        slideLeft = max(0, slideLeft - dt)
        wasCrouching = crouching
        wasSprinting = input.sprint && moving

        // --- Direction on the ground plane, from yaw alone.
        let forward = SIMD2<Float>(-sin(yaw), -cos(yaw))
        let right = SIMD2<Float>(cos(yaw), -sin(yaw))
        var direction = forward * input.forward + right * input.strafe
        let lengthSquared = simd_length_squared(direction)
        // **Clamped to 1, not normalised**, so holding two directions at once is not faster than one —
        // and a stick pushed a third of the way walks a third as fast. Normalising did the first and
        // broke the second: any deflection past the dead zone walked at full speed, so the stick's
        // response curve reached the look and never the feet. Measured before the fix: a stick at 5%
        // covered the same 6 m a second as one pushed all the way (0.9.0).
        if lengthSquared > 1 { direction /= lengthSquared.squareRoot() }

        // A slide goes where it was aimed when it started, nudged by the stick and no more.
        if slideLeft > 0 {
            let steered = slideDirection + direction * tuning.slideSteering
            direction = simd_length_squared(steered) > 0 ? steered / simd_length(steered) : slideDirection
        }

        // Crouched you walk, slowly. Sprinting from a crouch would make the posture free.
        var speed = crouching
            ? tuning.walkSpeed * tuning.crouchedSpeedFraction
            : (input.sprint ? tuning.sprintSpeed : tuning.walkSpeed)
        // Unless you are sliding, in which case the sprint's speed bleeds off into the crouch's —
        // held early and let go late, which reads as momentum rather than as being dragged to a halt.
        if slideLeft > 0 {
            let remaining = slideLeft / tuning.slideSeconds
            speed += (tuning.sprintSpeed - speed) * pow(remaining, tuning.slideEasing)
        }

        // --- Posture height, at a rate.
        let target = crouching ? tuning.crouchedEyeHeight : tuning.eyeHeight
        let rate = slideLeft > 0 ? tuning.postureRate * tuning.slideDropRate : tuning.postureRate
        height += max(-rate * dt, min(rate * dt, target - height))

        // --- Across: one axis at a time, so walking into a wall at an angle slides along it
        // rather than sticking. Refusing the whole move is what makes a wall feel like glue.
        let travel = direction * speed * dt
        let before = SIMD2(feet.x, feet.z)
        move(along: SIMD3(travel.x, 0, 0), in: world)
        move(along: SIMD3(0, 0, travel.y), in: world)

        // --- Up and down.
        stepVertically(jumpHeld: jump, deltaTime: dt, in: world)

        // --- Footfalls, from the distance **actually covered**, not the distance asked for. Pushing
        // into a wall asks for six metres a second and covers none; counting what was asked for is
        // the classic bug where a player standing against a wall marches on the spot.
        let covered = simd_distance(before, SIMD2(feet.x, feet.z))

        // --- The bob's amount: what this gait asks for, reached gradually. Nothing in the air and
        // nothing in a slide — neither has footfalls, and bobbing through a slide buried it.
        var wantBob: Float = 0
        if isGrounded && slideLeft == 0 && covered > 1e-5 && dt > 0 {
            let groundSpeed = covered / dt
            let gait: Float
            if crouching {
                gait = tuning.bobCrouchScale
            } else {
                let t = simd_clamp((groundSpeed - tuning.walkSpeed)
                                   / max(tuning.sprintSpeed - tuning.walkSpeed, 1e-3), 0, 1)
                gait = 1 + (tuning.bobSprintScale - 1) * t
            }
            // Slower than a walk — easing into one, or pressed against a wall — bobs less.
            let pace = crouching ? tuning.walkSpeed * tuning.crouchedSpeedFraction : tuning.walkSpeed
            wantBob = gait * min(1, groundSpeed / max(pace, 1e-3))
        }
        let ease = min(1, tuning.bobEase * dt)
        bobAmount += (wantBob - bobAmount) * ease
        if bobAmount < 1e-4 && wantBob == 0 { bobAmount = 0 }
        bobCatchUp *= 1 - min(1, tuning.settleRate * dt)

        if isGrounded && slideLeft == 0 && covered > 1e-5 && dt > 0 {
            if !wasMoving { setStridePhase(max(stridePhase, tuning.firstStepPhase)) }
            let groundSpeed = covered / dt
            stridePhase += covered / tuning.strideLength(atSpeed: groundSpeed, crouching: crouching)
            // **Not a slide**, which is excluded above: a slide is a body skidding, and footsteps at
            // sprint speed under it would be nine a second of feet that are not moving.
            while stridePhase >= 1 {
                stridePhase -= 1
                events.append(.stride(foot: nextFoot, speed: groundSpeed))
                nextFoot = nextFoot == .left ? .right : .left
            }
            wasMoving = true
        } else {
            wasMoving = false
        }

        // The eye catches up with the ground. Framed as a fraction per second, so the rate means the
        // same thing whatever the step is.
        settling *= 1 - min(1, tuning.settleRate * dt)

        // The knees: a critically damped spring, kicked by a landing and left to recover.
        //
        // **Stepped by its exact solution, not integrated.** The first version used semi-implicit
        // Euler — stable, and 20% shy of the depth it was kicked to at 120 Hz, which a test caught.
        // A critically damped spring has a closed form, so there is no reason to approximate one:
        // this lands on the same curve at any step size.
        let omega = tuning.landingSpring
        let decay = exp(-omega * dt)
        let x0 = landingCompression, v0 = compressionRate
        landingCompression = max(0, (x0 + (v0 + omega * x0) * dt) * decay)
        compressionRate = (v0 - omega * (v0 + omega * x0) * dt) * decay
        if simd_length_squared(direction) > 0 { lastDirection = direction }
    }

    // MARK: - Across

    private mutating func move(along delta: SIMD3<Float>, in world: Surroundings) {
        guard delta != .zero else { return }
        let candidate = feet + delta

        // What would be in the way, above the soles of the feet.
        let obstructions = obstructing(at: candidate, in: world)
        guard let rise = obstructions.map(\.maximum.y).max() else {
            feet = candidate
            return
        }

        // **A step, if it is low enough and there is room on top of it.** Only from the ground: a
        // body in the air that catches a ledge with its shins has not stepped onto it.
        let climb = rise - feet.y
        if isGrounded, climb <= tuning.stepHeight {
            let raised = SIMD3(candidate.x, rise, candidate.z)
            if obstructing(at: raised, in: world).isEmpty {
                // The feet go up at once and the eye follows — see the type's notes on smoothing.
                settling -= climb
                feet = raised
                footOnRise(climb)
                return
            }
        }
        // Otherwise this axis is blocked — but **as far as the face, not a whole step short of it.**
        // Refusing the move outright stops the player wherever the last step happened to end: four
        // centimetres from a wall at a walk, fifteen at a sprint, and a gap you can see when you
        // turn to look at it. Measured in the sample before this line existed.
        let axis = delta.x != 0 ? 0 : 2
        let forward = delta[axis] > 0
        let gap = tuning.radius + 2 * CharacterController.contactTolerance
        var reach = candidate[axis]
        for solid in obstructions {
            reach = forward ? min(reach, solid.minimum[axis] - gap) : max(reach, solid.maximum[axis] + gap)
        }
        // Only ever onward: a body already inside something must not be pulled backwards through it.
        if forward ? reach > feet[axis] : reach < feet[axis] { feet[axis] = reach }
        // The other axis still gets its turn.
    }

    /// **A step up is a foot landing on something**, whatever the stride says.
    ///
    /// At these speeds a stride is longer than a stair tread, so counting distance alone climbs four
    /// treads in two footsteps — which sounds like floating up the middle two.
    ///
    /// > **Called from both places a body rises, and the first version was only in one.** The climb
    /// > in ``move(along:in:)`` is what the code *looked* like it did on stairs; in fact the footprint's
    /// > leading edge usually reaches a tread first, and the ground-following in the vertical step
    /// > lifts the body before any move is refused. A test counting footsteps per tread found it — two
    /// > for four treads, with the rule written and apparently working.
    ///
    /// Not for a rise under 12 cm in a step, which is a slope rather than a stair, and not if a
    /// footstep has only just sounded, or a tread taken mid-stride would ring twice.
    ///
    /// **The head bob would jump with it**, from wherever the stride was to a footfall — up to three
    /// centimetres in one frame, on every tread. So ``setStridePhase(_:)`` puts the jump into
    /// ``bobCatchUp``, which eases out at the eye's own settling rate: the head bob follows a step the
    /// way the eye does.
    private mutating func footOnRise(_ climb: Float) {
        if climb > 0.12 && stridePhase > CharacterController.stepUpFootfall { setStridePhase(1) }
    }

    /// Moves the stride phase somewhere it did not walk to — a footfall on a step, the first step
    /// setting off, a landing — **carrying the head bob across the jump** rather than snapping it.
    private mutating func setStridePhase(_ phase: Float) {
        let before = rawBob
        stridePhase = phase
        bobCatchUp += before - rawBob
    }

    /// Every solid the body would overlap, standing at `position`.
    ///
    /// **Above the soles only**: a solid whose top is at or below the feet is being stood on, not
    /// walked into. Without that allowance, standing on a crate is overlapping it, and every step
    /// across its top is refused.
    private func obstructing(at position: SIMD3<Float>, in world: Surroundings) -> [BoundingBox] {
        let box = body(at: position, eyeHeight: height)
        return world.solids.filter { overlaps(box, $0, allowingFloorAt: position.y) }
    }

    // MARK: - Up and down

    private mutating func stepVertically(jumpHeld: Bool, deltaTime dt: Float, in world: Surroundings) {
        // A jump is a *press*, remembered briefly so one pressed just before landing still counts.
        if jumpHeld && !wasJumpHeld { jumpBufferLeft = tuning.jumpBufferSeconds }
        wasJumpHeld = jumpHeld
        jumpBufferLeft = max(0, jumpBufferLeft - dt)
        coyoteLeft = isGrounded ? tuning.coyoteSeconds : max(0, coyoteLeft - dt)

        // **Not out of a slide.** A slide is committed; a jump out of it at sprint speed is exactly
        // the movement tech the slide's own tuning forbids.
        if jumpBufferLeft > 0 && coyoteLeft > 0 && slideLeft == 0 {
            verticalVelocity = tuning.jumpSpeed
            isGrounded = false
            groundSolid = nil
            jumpBufferLeft = 0
            coyoteLeft = 0
            events.append(.jumped)
        }

        if isGrounded {
            // Stay on the ground as it changes under you: up a slope, down a step, onto the next bump.
            let (support, solid) = supportHeight(at: feet, below: feet.y + tuning.stepHeight, in: world)
            if support >= feet.y - tuning.stepHeight {
                footOnRise(support - feet.y)
                settling -= support - feet.y
                feet.y = support
                verticalVelocity = 0
                groundSolid = solid
                return
            }
            // Walked off something taller than a step: now falling, from rest.
            isGrounded = false
            groundSolid = nil
            verticalVelocity = 0
        }

        verticalVelocity -= tuning.gravity * dt
        var next = feet.y + verticalVelocity * dt

        if verticalVelocity > 0 {
            // A head against the underside of something stops the rise there.
            let top = next + tuning.bodyHeight(for: height)
            if let ceiling = lowestCeiling(above: feet, reaching: top, in: world) {
                next = ceiling - tuning.bodyHeight(for: height)
                verticalVelocity = 0
            }
        } else {
            // Landing: the highest thing under the footprint that was below the feet a moment ago.
            // **Measured from where the feet were, not where they are going**, so a fast fall
            // cannot skip through a thin floor between two steps.
            let (support, solid) = supportHeight(at: feet, below: feet.y, in: world)
            if next <= support {
                // **Speed at the moment of contact**, before it is zeroed — the number a landing's
                // loudness, a camera dip or fall damage all want.
                events.append(.landed(impactSpeed: -verticalVelocity))
                // **A kick, not a position**: the spring's velocity is what the landing sets, so the
                // eye travels down to its lowest rather than teleporting there. For a critically
                // damped spring from rest, an initial rate of ω·e·s peaks at exactly s.
                let span = max(tuning.landingHardImpact - tuning.landingSoftImpact, 1e-3)
                let strength = simd_clamp((-verticalVelocity - tuning.landingSoftImpact) / span, 0, 1)
                compressionRate += strength * tuning.landingSpring * Float(M_E)
                next = support
                verticalVelocity = 0
                isGrounded = true
                groundSolid = solid
                // Both feet just came down; the next footfall is a whole stride away.
                setStridePhase(0)
            }
        }
        feet.y = next
    }

    /// The highest surface under the footprint whose top is no higher than `limit`.
    ///
    /// **Terrain always counts**, whatever the limit — it is the floor, and nothing goes below it.
    /// Solids count only if they are low enough to be under the feet rather than in front of them.
    ///
    /// Returns which solid it was, too — nil when the terrain is highest.
    private func supportHeight(at position: SIMD3<Float>, below limit: Float,
                               in world: Surroundings) -> (height: Float, solid: Int?) {
        var highest = world.groundHeight(position.x, position.z)
        var which: Int?
        let r = tuning.radius
        for (index, solid) in world.solids.enumerated()
        where solid.maximum.y <= limit + CharacterController.contactTolerance
            && position.x + r > solid.minimum.x && position.x - r < solid.maximum.x
            && position.z + r > solid.minimum.z && position.z - r < solid.maximum.z
            && solid.maximum.y > highest {
            highest = solid.maximum.y
            which = index
        }
        return (highest, which)
    }

    /// The lowest underside of anything the head would rise into, or nil.
    private func lowestCeiling(above position: SIMD3<Float>, reaching top: Float,
                               in world: Surroundings) -> Float? {
        let r = tuning.radius
        let head = position.y + tuning.bodyHeight(for: height)
        var lowest: Float?
        for solid in world.solids
        where solid.minimum.y >= head - CharacterController.contactTolerance && solid.minimum.y < top
            && position.x + r > solid.minimum.x && position.x - r < solid.maximum.x
            && position.z + r > solid.minimum.z && position.z - r < solid.maximum.z {
            lowest = min(lowest ?? .greatestFiniteMagnitude, solid.minimum.y)
        }
        return lowest
    }

    // MARK: - Geometry

    /// How close two surfaces have to be to count as touching rather than overlapping.
    ///
    /// **A millimetre, and not zero.** Feet placed exactly on a crate's top are at the same float as
    /// the top; one rounding step later they are a hair inside it, and a strict test calls that an
    /// overlap and refuses the next step across the crate.
    static let contactTolerance: Float = 1e-3

    /// How far through a stride a step up has to be before it counts as a footfall of its own.
    static let stepUpFootfall: Float = 0.3

    private func body(at position: SIMD3<Float>, eyeHeight: Float) -> BoundingBox {
        let r = tuning.radius
        return BoundingBox(minimum: SIMD3(position.x - r, position.y, position.z - r),
                           maximum: SIMD3(position.x + r, position.y + tuning.bodyHeight(for: eyeHeight),
                                          position.z + r))
    }

    private func overlaps(_ body: BoundingBox, _ solid: BoundingBox, allowingFloorAt floor: Float) -> Bool {
        let t = CharacterController.contactTolerance
        return body.maximum.x > solid.minimum.x + t && body.minimum.x < solid.maximum.x - t
            && body.maximum.z > solid.minimum.z + t && body.minimum.z < solid.maximum.z - t
            && body.maximum.y > solid.minimum.y + t && solid.maximum.y > floor + t
    }
}
