# Human first look: cp-06 (optional, 10 minutes)

You do not have to do this. The checks run by themselves without you: the unit and level tests, the feedback bench, the screenshot tour. What a machine cannot judge is how the game feels. This list is for that, and only that.

**What you need:** the exported build for your platform (the zip from `tools/ci/export.sh`; unzip it anywhere). Windows: run `NOCLIP.exe`. Linux: run `./NOCLIP.x86_64`. A computer with a Vulkan graphics card, a keyboard and a mouse. Headphones help.

**How to use this list:** play for about ten minutes, in order. For each item do the thing, look and listen for what is written, and write down one word or one line: `fine`, `wrong`, or what you noticed. Nothing here is a test you can fail. If an item does not work or you cannot find the thing, write `could not` and move on. Do not read the design documents first.

**Controls**

| | |
|---|---|
| Move | W A S D |
| Look | Mouse |
| Sprint | hold Left Shift |
| Crouch | hold Left Ctrl |
| Interact | E |
| Flashlight | F |
| Crank the flashlight | hold R |
| Noclip | hold Left Mouse Button; let go to cancel |
| Use item | Right Mouse Button |
| Pick item | 1 to 4 or the mouse wheel |

To quit, close the window.

---

## The list

**1. The title.** Start the game. Choose DESCEND with the mouse or the arrow keys and Enter.
Look for: a black screen with the word NOCLIP; the menu; a short glitch cut into the game.
Write down: did it take longer than about three seconds to be in control?

**2. The mouse.** Click once if the mouse is not captured. Turn slowly all the way round, then fast. Then walk forward with W while turning.
Look for: the view following your hand exactly, with no lag, no rubber band, and no stutter or judder when you turn while walking (the stutter is the thing the team is worried about; watch the edges of the walls as you turn).
Write down: smooth, or any judder? Is the speed too fast or too slow?

**3. Walking, sprinting, crouching.** Walk down the first corridor. Hold Shift to sprint for a few seconds. Hold Ctrl to crouch.
Look and listen for: a footstep on every stride (it should sound like carpet); a very slight bob of the camera and of the light; the view widening a little when you sprint, with a breath that fades in; a small arc under the crosshair that drains while you sprint and goes red when you run out, with a gasp; the camera dropping when you crouch.
Write down: does the bob feel right, too much, or nothing? Is the sprint breath natural, or does it sound like a machine?

**4. The dark and the light.** Stand still where the corridor is dim. Look at the floor in the distance. Press F.
Look and listen for: a relay click and a beam with a small light at your hand; pools of light on the ceiling every few metres, with a low electrical hum; the floor still readable (a little) with your light off, so that you never lose your way.
Write down: with the light off, can you see where to walk? Is anything pure black, or pure white?

**5. The crank.** Press F so the light is on, wait until the percent at bottom left has dropped a little, then hold R.
Look and listen for: a ratchet clicking with a rising whine as the percent climbs; the camera swaying slowly; a bright click when it reaches full. Cranking is loud on purpose: in the game, things hear it.
Write down: does the whine rise, and is the click at the top satisfying?

**6. Noclip through a wall.** Find an ordinary wall in a corridor. Stand about a metre away, look at it, and hold the Left Mouse Button until it happens.
Look and listen for: a ring filling around the crosshair and a dotted disc growing on the wall; a rising tone; your flashlight dimming and the view pulling in as you charge. At the end: a thump and a tearing sound, a short freeze, the view punching outward, the lines of the walls around you flaring, and you standing on the other side. Your Coherence (top left) drops by 10.
Write down: is the freeze at the moment of the pass felt as a hit, or as a lag? Does the 250 ms slide through the wall feel good?

**7. Letting go, and refusing.** Hold the button on a wall, then let go halfway. Then aim at the edge of the whole level (a thick outer wall, or a spot with nothing behind it) and hold.
Look and listen for: a falling tone and the ring emptying when you let go; for the refused wall, a dashed ring, a dull tone once, and a word under the crosshair (SOLID, NO SPACE, TOO FAR).
Write down: did you understand why it refused, without being told?

**8. Coherence you can see.** Pass through two or three more walls without looking for anything else, so that Coherence falls below 50, then below 30.
Look for: the picture losing its colour, getting grainy, the corners darkening, the edges splitting into red and blue; at about 25 the numbers turn red and a heartbeat starts.
Write down: could you tell your Coherence from the picture alone, with your eyes off the top-left bar?

**9. A soft wall.** Look for a wall that shimmers slightly. Try to pass it.
Look and listen for: a charge that is much quicker (about a third of a second) and cheaper (5).
Write down: could you tell it apart from other walls without being told? Did it feel like a discovery?

**10. Things you can pick up.** Walk up to anything lying on the floor and press E (a note; a Polaroid, a chalk, or a glowstick). Read the note. Then use each item with the Right Mouse Button: the Polaroid (hold it up, a flash, Coherence goes up), the chalk (aim at a wall, an arrow appears), the glowstick (tap to throw, hold to set down quietly).
Look and listen for: paper sliding, the note typing itself out; the item changing in your hand; the count at bottom right going down.
Write down: which item felt best in the hand, and which felt like nothing?

**11. Hiding.** Find a locker (a tall grey box along a wall). Press E on it. Look around. Hold E to come out.
Look and listen for: the camera sliding into the locker, slits across the view, your own breathing, the HUD going dim with an eye in place of the crosshair.
Write down: does it feel safe, or just dark?

**12. Static.** If you meet a patch of air that looks like moving noise, or you hear a low hum coming through a wall, go towards it, step inside, then step out.
Look and listen for: the hum getting closer through walls; inside, a rising noise band, a grainy refracting picture, the camera trembling slightly, and Coherence draining at about four a second.
Write down: did you know what to do (go around it, wait, or pass through a wall)?

**13. The exit and the breaker.** Find the elevator (a door set in the wall, a lamp above it). The first one is dead and dark. Find the grey breaker box on a wall nearby, face it, and hold E.
Look and listen for: `EXIT: POWERED` at top right turning into a notice; the lever dropping with a heavy clunk and a small shake; light flooding the corridors in a wave from the box towards the elevator, tube by tube; the elevator doors opening with a latch and a hiss; the status turning to `OPEN`. Walk in.
Write down: was it clear what to do without being told? Did the wave of light feel like a reward?

**14. The cabin.** You are in a small metal cabin that shudders and hums while the next level builds, with a panel offering two items.
Look and listen for: the shudder, the hum, one ripple of the world unrendering across the room, the panel with `COHERENCE +20`, a choice you make with 1 or 2 or a click, the door opening, and your Coherence going up.
Write down: did you feel safe in it, or trapped? Was six seconds too long or too short?

**15. Still, and the loop.** On the second level (and later) watch for a matte black column, taller than you, standing in the dark. If you see one: switch your light on and look straight at it, then look away, or turn the light off. Let it reach you once if you dare. Whenever you die, read the summary, then press DESCEND again.
Look and listen for: it never moves while you look at it in the light; the room going very quiet when it is near, with a thin high blip every couple of seconds while you hold your look; when it touches you, a heavy hit, a shove, and a moment when you cannot control the camera. After dying: the picture breaking into little squares, a summary that tells you why, and how fast you are back in the game.
Write down: was Still frightening, or irritating? Did you want to go again straight away?

---

## At the end

Two lines:

1. The one moment you most want to keep.
2. The one thing that felt worst. Nothing is too small; "it felt cheap" is a good answer.

Put this file, with your answers, next to the build or paste it into the conversation. The orchestrator reads it as feel notes, not as bugs.
