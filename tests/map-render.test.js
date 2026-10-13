const test = require("node:test")
const assert = require("node:assert/strict")
const MapRender = require("../MapRender.js")

test("edge planning rejects duplicate directed routes without mutating input", () => {
  const edges = [
    { from: "room-1", to: "room-2", direction: "north" },
    { from: "room-1", to: "room-2", direction: "north" }
  ]
  const before = JSON.parse(JSON.stringify(edges))

  assert.deepEqual(MapRender.planEdges(edges), {
    valid: false,
    reason: "duplicate directed edge",
    edges: []
  })
  assert.deepEqual(edges, before)
})

test("edge planning derives reciprocal metadata in linear lookup passes", () => {
  const forward = { from: "room-1", to: "room-2", direction: "north" }
  const parallel = { from: "room-1", to: "room-2", direction: "northeast" }
  const reverse = { from: "room-2", to: "room-1", direction: "south" }
  const oneWay = { from: "room-2", to: "room-3", direction: "east" }
  const selfLoop = { from: "room-3", to: "room-3", direction: "down" }
  const plan = MapRender.planEdges([forward, parallel, reverse, oneWay, selfLoop])

  assert.equal(plan.valid, true)
  assert.deepEqual(plan.edges.map(edge => edge.hasReverse), [true, true, true, false, false])
  assert.equal(plan.edges[0].pairKey, plan.edges[1].pairKey)
  assert.equal(plan.edges[0].pairKey, plan.edges[2].pairKey)
  assert.equal(plan.edges[4].edge, selfLoop)
})

test("edge planning handles the renderer maximum in bounded lookup passes", () => {
  const directions = ["north", "east", "south", "west"]
  const edges = []
  for (let index = 0; index < 16384; index++) {
    const batch = Math.floor(index / 4096)
    const source = index % 4096
    edges.push({
      from: `room-${source + 1}`,
      to: `room-${(source + batch + 1) % 4096 + 1}`,
      direction: directions[batch]
    })
  }

  const plan = MapRender.planEdges(edges)
  assert.equal(plan.valid, true)
  assert.equal(plan.edges.length, 16384)
})

function rectanglesOverlap(left, right, gutter = 13.99) {
  return Math.abs(left.x - right.x) < (left.width + right.width) / 2 + gutter &&
    Math.abs(left.y - right.y) < (left.height + right.height) / 2 + gutter
}

function assertNoNodeOverlaps(nodes) {
  for (let left = 0; left < nodes.length; left++)
    for (let right = left + 1; right < nodes.length; right++)
      assert.equal(rectanglesOverlap(nodes[left], nodes[right]), false,
        `${nodes[left].id} overlaps ${nodes[right].id}`)
}

test("node layout deterministically separates logical and projected collisions without mutation", () => {
  const nodes = [
    { id: "room-1", anchorX: 0, anchorY: 0, width: 108, height: 58 },
    { id: "room-2", anchorX: 0, anchorY: 0, width: 108, height: 58 },
    { id: "room-3", anchorX: 46, anchorY: -72, width: 108, height: 58 },
    { id: "room-4", anchorX: 148, anchorY: 0, width: 108, height: 58 }
  ]
  const before = JSON.parse(JSON.stringify(nodes))
  const first = MapRender.planNodeLayout(nodes)
  const second = MapRender.planNodeLayout(nodes)

  assert.equal(first.valid, true)
  assert.deepEqual(first, second)
  assert.deepEqual(nodes, before)
  assertNoNodeOverlaps(first.nodes)
  assert.equal(first.nodes[0].displaced, false)
  assert.ok(first.nodes.slice(1).some(node => node.displaced))
})

test("node layout remains collision-free for dense progression and preserves existing placements", () => {
  const dense = Array.from({ length: 80 }, (_, index) => ({
    id: `room-${index + 1}`,
    anchorX: index % 3 === 0 ? 148 : 0,
    anchorY: index % 5 === 0 ? 106 : 0,
    width: 108,
    height: 58
  }))
  const initial = MapRender.planNodeLayout(dense.slice(0, 40))
  const grown = MapRender.planNodeLayout(dense)

  assert.equal(initial.valid, true)
  assert.equal(grown.valid, true)
  assertNoNodeOverlaps(grown.nodes)
  assert.deepEqual(grown.nodes.slice(0, 40), initial.nodes)
})

test("overflow lane and numeric room ordering remain stable when distant rooms append", () => {
  const crowded = Array.from({ length: 650 }, (_, index) => ({
    id: `room-${index + 1}`,
    anchorX: 0,
    anchorY: 0,
    width: 108,
    height: 58
  }))
  const initial = MapRender.planNodeLayout(crowded)
  const grown = MapRender.planNodeLayout(crowded.concat({
    id: "room-651",
    anchorX: 10000,
    anchorY: 0,
    width: 108,
    height: 58
  }))

  assert.equal(initial.valid, true)
  assert.ok(initial.overflowCount > 0)
  assert.equal(grown.valid, true)
  assert.deepEqual(grown.nodes.slice(0, crowded.length), initial.nodes)
  assert.ok(MapRender.roomOrder("room-9") < MapRender.roomOrder("room-10"))
})

test("fit viewport defaults to a restrained whole-map view", () => {
  const bounds = { left: -300, top: -180, right: 500, bottom: 260 }
  const fitted = MapRender.fitViewport(bounds, 750, 456, 0.55, 1.35, 0.88)

  assert.equal(fitted.panX, -100)
  assert.equal(fitted.panY, -40)
  assert.ok(fitted.zoom >= 0.55 && fitted.zoom < 0.88)
})

test("viewport clamp permits bounded keyboard and pointer panning for small maps", () => {
  const bounds = { left: -108, top: -87, right: 108, bottom: 87 }
  const centered = MapRender.clampViewport(bounds, 750, 456, 0.85, 0, 0)
  const moved = MapRender.clampViewport(bounds, 750, 456, 0.85, 64, -64)
  const excessive = MapRender.clampViewport(bounds, 750, 456, 0.85, 100000, -100000)

  assert.deepEqual(centered, { panX: 0, panY: 0 })
  assert.deepEqual(moved, { panX: 64, panY: -64 })
  assert.ok(Math.abs(excessive.panX) < 250)
  assert.ok(Math.abs(excessive.panY) < 150)
})

test("route insets stop horizontal and vertical arrows outside room boxes", () => {
  assert.equal(MapRender.routeInset(108, 58, 100, 0, 6), 60)
  assert.equal(MapRender.routeInset(108, 58, 0, 100, 6), 35)
  const diagonal = MapRender.routeInset(108, 58, 100, 100, 6)
  assert.ok(diagonal > 35 && diagonal < 60)
})

test("accessible exits follow semantic compass and vertical order", () => {
  const shuffled = [
    { from: "room-1", direction: "out" },
    { from: "room-1", direction: "southwest" },
    { from: "room-2", direction: "north" },
    { from: "room-1", direction: "north" },
    { from: "room-1", direction: "down" },
    { from: "room-1", direction: "northeast" },
    { from: "room-1", direction: "in" },
    { from: "room-1", direction: "east" },
    { from: "room-1", direction: "north" },
    { from: "room-1", direction: "up" },
    { from: "room-1", direction: "northwest" },
    { from: "room-1", direction: "southeast" },
    { from: "room-1", direction: "west" },
    { from: "room-1", direction: "south" }
  ]

  assert.deepEqual(MapRender.orderedExitLabels(shuffled, "room-1"), [
    "N", "NE", "E", "SE", "S", "SW", "W", "NW", "U", "D", "IN", "OUT"
  ])
})
