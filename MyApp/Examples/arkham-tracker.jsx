// @name Arkham Tracker
// @type react
// @icon 🐙

// Globals: React, db

const { useState, useEffect, useCallback } = React;

// All Arkham records live in one collection. The `type` property distinguishes
// scenarios, locations, enemies, investigators and random generators.
const elements = db.collection("arkhamElements");

// ── Counter colors — reused across types ──
const COLORS = {
    actions:   "#eef0f2",
    health:    "#e5484d",
    horror:    "#4a9bf2",
    clues:     "#5ac46a",
    resources: "#f2c94c",
    doom:      "#b072f0",
    act:       "#7fa386",
    agenda:    "#9b8fb5",
};

// ── The unified model: every element is just "a thing with counters" ──
const TYPES = {
    scenario: {
        label: "Scenario",
        counters: [
            { key: "act",    label: "Act",    color: COLORS.act },
            { key: "agenda", label: "Agenda", color: COLORS.agenda },
            { key: "doom",   label: "Doom",   color: COLORS.doom },
        ],
        hasLocation: false,
    },
    location: {
        label: "Location",
        counters: [
            { key: "clues", label: "Clues", color: COLORS.clues },
        ],
        hasLocation: false,
    },
    enemy: {
        label: "Enemy",
        counters: [
            { key: "health", label: "Health", color: COLORS.health },
            { key: "doom",   label: "Doom",   color: COLORS.doom },
        ],
        hasLocation: true,
    },
    player: {
        label: "Investigator",
        counters: [
            { key: "actions",   label: "Actions",   color: COLORS.actions },
            { key: "health",    label: "Health",    color: COLORS.health },
            { key: "horror",    label: "Horror",    color: COLORS.horror },
            { key: "clues",     label: "Clues",     color: COLORS.clues },
            { key: "resources", label: "Resources", color: COLORS.resources },
        ],
        hasLocation: true,
    },
};

const C = {
    card: "#1e2127",
    border: "#2a2e37",
    text: "#e8e8ea",
    muted: "#8a8f98",
    accent: "#6cc24a",
};

const stepBtn = {
    width: 30,
    height: 30,
    borderRadius: 6,
    border: "none",
    background: "#2a2e37",
    color: C.text,
    fontSize: 18,
    fontWeight: 700,
    cursor: "pointer",
    lineHeight: 1,
};

const inputS = {
    flex: 1,
    minWidth: 0,
    padding: "8px 10px",
    borderRadius: 6,
    border: `1px solid ${C.border}`,
    background: "#16181d",
    color: C.text,
    fontSize: 16,
};

const addBtn = {
    padding: "8px 16px",
    borderRadius: 6,
    border: "none",
    background: C.accent,
    color: "#0c1108",
    fontWeight: 700,
    cursor: "pointer",
};

const selectS = {
    padding: "5px 8px",
    borderRadius: 6,
    border: `1px solid ${C.border}`,
    background: "#16181d",
    color: C.text,
    fontSize: 16,
};

const cardS = {
    background: C.card,
    border: `1px solid ${C.border}`,
    borderRadius: 10,
    padding: 14,
    marginBottom: 10,
};

function Counter({ label, value, color, onDelta }) {
    return (
        <div
            style={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                gap: 4,
                minWidth: 62,
            }}
        >
            <span
                style={{
                    fontSize: 10,
                    letterSpacing: 0.6,
                    textTransform: "uppercase",
                    color: C.muted,
                }}
            >
                {label}
            </span>

            <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                <button
                    type="button"
                    onClick={() => onDelta(-1)}
                    style={stepBtn}
                >
                    –
                </button>

                <span
                    style={{
                        minWidth: 22,
                        textAlign: "center",
                        fontSize: 20,
                        fontWeight: 700,
                        color,
                    }}
                >
                    {value}
                </span>

                <button
                    type="button"
                    onClick={() => onDelta(1)}
                    style={stepBtn}
                >
                    +
                </button>
            </div>
        </div>
    );
}

// ── One card renders any element type ──
function ElementCard({
                         el,
                         type,
                         locations,
                         onDelta,
                         onLocation,
                         onRemove,
                     }) {
    const currentLoc = locations.some(
        (location) => location.id === el.locationId
    )
        ? el.locationId
        : "";

    return (
        <div style={cardS}>
            <div
                style={{
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "center",
                    marginBottom: 10,
                }}
            >
                <strong style={{ color: C.text }}>{el.name}</strong>

                {onRemove && (
                    <button
                        type="button"
                        onClick={onRemove}
                        aria-label={`Delete ${el.name}`}
                        style={{
                            border: "none",
                            background: "transparent",
                            color: C.muted,
                            cursor: "pointer",
                            fontSize: 14,
                        }}
                    >
                        ✕
                    </button>
                )}
            </div>

            <div style={{ display: "flex", flexWrap: "wrap", gap: 12 }}>
                {type.counters.map((counter) => (
                    <Counter
                        key={counter.key}
                        label={counter.label}
                        color={counter.color}
                        value={el.counters?.[counter.key] ?? 0}
                        onDelta={(amount) => onDelta(counter.key, amount)}
                    />
                ))}
            </div>

            {type.hasLocation && (
                <div style={{ marginTop: 10 }}>
                    <label
                        style={{
                            fontSize: 12,
                            color: C.muted,
                            marginRight: 6,
                        }}
                    >
                        Location
                    </label>

                    <select
                        value={currentLoc}
                        onChange={(event) => onLocation(event.target.value)}
                        style={selectS}
                    >
                        <option value="">—</option>

                        {locations.map((location) => (
                            <option key={location.id} value={location.id}>
                                {location.name}
                            </option>
                        ))}
                    </select>
                </div>
            )}
        </div>
    );
}

function Section({ title, children }) {
    return (
        <div style={{ marginBottom: 22 }}>
            <h3
                style={{
                    margin: "0 0 10px",
                    fontSize: 13,
                    letterSpacing: 1.5,
                    textTransform: "uppercase",
                    color: C.accent,
                }}
            >
                {title}
            </h3>

            {children}
        </div>
    );
}

// Kept at module scope so the input retains focus on mobile.
function AddRow({ type, value, onChange, onAdd }) {
    function submit(event) {
        event.preventDefault();
        onAdd();
    }

    return (
        <form
            onSubmit={submit}
            style={{
                display: "flex",
                gap: 8,
                marginBottom: 12,
            }}
        >
            <input
                type="text"
                value={value}
                placeholder={`Add ${TYPES[type].label.toLowerCase()}…`}
                onChange={(event) => onChange(event.target.value)}
                style={inputS}
            />

            <button type="submit" style={addBtn}>
                Add
            </button>
        </form>
    );
}

function DeleteDialog({ element, onCancel, onConfirm }) {
    if (!element) {
        return null;
    }

    const description =
        element.type === "random"
            ? "this random generator"
            : `"${element.name}"`;

    return (
        <div
            role="presentation"
            onClick={onCancel}
            style={{
                position: "fixed",
                inset: 0,
                zIndex: 1000,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                padding: 20,
                background: "#000000aa",
            }}
        >
            <div
                role="alertdialog"
                aria-modal="true"
                aria-labelledby="delete-dialog-title"
                onClick={(event) => event.stopPropagation()}
                style={{
                    width: "min(100%, 360px)",
                    padding: 20,
                    borderRadius: 12,
                    border: `1px solid ${C.border}`,
                    background: C.card,
                    boxShadow: "0 16px 48px #00000088",
                }}
            >
                <h2
                    id="delete-dialog-title"
                    style={{ margin: "0 0 8px", fontSize: 20 }}
                >
                    Confirm deletion
                </h2>

                <p style={{ margin: "0 0 20px", color: C.muted }}>
                    Delete {description}? This cannot be undone.
                </p>

                <div
                    style={{
                        display: "flex",
                        justifyContent: "flex-end",
                        gap: 8,
                    }}
                >
                    <button
                        type="button"
                        onClick={onCancel}
                        style={{
                            ...addBtn,
                            background: C.border,
                            color: C.text,
                        }}
                    >
                        Cancel
                    </button>

                    <button
                        type="button"
                        onClick={onConfirm}
                        style={{
                            ...addBtn,
                            background: COLORS.health,
                            color: "#fff",
                        }}
                    >
                        Delete
                    </button>
                </div>
            </div>
        </div>
    );
}

// ── Random generator ──
//
// Pattern:
//   "N: bag"
//
// The bag can be:
//   x..y  → integers x through y
//   abc…  → individual graphemes; whitespace is ignored
//
// Draws are made without replacement.
const randInt = (min, max) =>
    Math.floor(Math.random() * (max - min + 1)) + min;

function bagItems(bag) {
    const range = bag.match(/^(-?\d+)\s*\.\.\s*(-?\d+)$/);

    if (range) {
        let a = parseInt(range[1], 10);
        let b = parseInt(range[2], 10);

        if (a > b) {
            [a, b] = [b, a];
        }

        return Array.from(
            { length: b - a + 1 },
            (_, index) => String(a + index)
        );
    }

    const segmenter = new Intl.Segmenter(undefined, {
        granularity: "grapheme",
    });

    return [...segmenter.segment(bag)]
        .map((entry) => entry.segment)
        .filter((item) => item.trim() !== "");
}

function rollInput(raw) {
    const match = raw.trim().match(/^(\d+)\s*:\s*(.+)$/);

    if (!match) {
        return "?";
    }

    const count = parseInt(match[1], 10);
    const items = bagItems(match[2]);

    if (count < 1 || items.length === 0) {
        return "?";
    }

    const picks = [];

    for (let index = 0; index < count && items.length > 0; index += 1) {
        const selectedIndex = randInt(0, items.length - 1);
        picks.push(items.splice(selectedIndex, 1)[0]);
    }

    return picks.join(" ");
}

function RandomGen({ value, onChange, onRemove }) {
    const [result, setResult] = useState("");

    function roll() {
        setResult(rollInput(value));
    }

    function submit(event) {
        event.preventDefault();
        roll();
    }

    return (
        <div style={cardS}>
            <form
                onSubmit={submit}
                style={{ display: "flex", gap: 8 }}
            >
                <input
                    type="text"
                    value={value}
                    placeholder="e.g. 1: 0..99 or 3: 💀💀⭐️🦑"
                    onChange={(event) => onChange(event.target.value)}
                    style={inputS}
                />

                <button
                    type="button"
                    onClick={onRemove}
                    title="Delete"
                    aria-label="Delete random generator"
                    style={{
                        ...stepBtn,
                        width: 36,
                        color: C.muted,
                        fontSize: 14,
                    }}
                >
                    ✕
                </button>

                <button type="submit" style={addBtn}>
                    Roll
                </button>
            </form>

            {result !== "" && (
                <div
                    style={{
                        marginTop: 10,
                        fontSize: 26,
                        textAlign: "center",
                        color: C.text,
                        letterSpacing: 2,
                    }}
                >
                    {result}
                </div>
            )}
        </div>
    );
}

function App() {
    const [els, setEls] = useState([]);
    const [loaded, setLoaded] = useState(false);
    const [error, setError] = useState("");
    const [pendingRemoval, setPendingRemoval] = useState(null);

    const [drafts, setDrafts] = useState({
        location: "",
        enemy: "",
        player: "",
    });

    // New collection API:
    //   orderBy is a field name
    //   desc controls the direction
    const load = useCallback(async () => {
        try {
            setError("");

            let all = await elements.list({
                orderBy: "createdAt",
                desc: false,
            });

            // Ensure that this collection always has one scenario record.
            if (!all.some((element) => element.type === "scenario")) {
                await elements.create({
                    type: "scenario",
                    name: "Scenario",
                    counters: {
                        act: 1,
                        agenda: 1,
                        doom: 0,
                    },
                    createdAt: Date.now(),
                });

                all = await elements.list({
                    orderBy: "createdAt",
                    desc: false,
                });
            }

            setEls(all);
        } catch (err) {
            console.error("Could not load Arkham data:", err);
            setError(err?.message || "Could not load Arkham data.");
        } finally {
            setLoaded(true);
        }
    }, []);

    useEffect(() => {
        load();
    }, [load]);

    // Restore database state if an optimistic update fails.
    const recoverFromWriteError = useCallback(
        (operation, err) => {
            console.error(`Could not ${operation}:`, err);
            setError(`Could not ${operation}. Data has been reloaded.`);
            load();
        },
        [load]
    );

    // Optimistic counter update, persisted through the collection.
    function delta(id, key, amount) {
        const element = els.find((item) => item.id === id);

        if (!element) {
            return;
        }

        const counters = {
            ...element.counters,
            [key]: Math.max(
                0,
                (element.counters?.[key] ?? 0) + amount
            ),
        };

        setEls((previous) =>
            previous.map((item) =>
                item.id === id
                    ? { ...item, counters }
                    : item
            )
        );

        elements
            .update(id, { counters })
            .catch((err) => recoverFromWriteError("update counter", err));
    }

    // The random expression is persisted as it is edited.
    function setRandomValue(id, value) {
        setEls((previous) =>
            previous.map((item) =>
                item.id === id
                    ? { ...item, value }
                    : item
            )
        );

        elements
            .update(id, { value })
            .catch((err) =>
                recoverFromWriteError("update random generator", err)
            );
    }

    async function addRandom() {
        try {
            setError("");

            const slot =
                els.reduce((highest, element) => {
                    if (
                        element.type !== "random" ||
                        !Number.isFinite(element.slot)
                    ) {
                        return highest;
                    }

                    return Math.max(highest, element.slot);
                }, -1) + 1;

            await elements.create({
                type: "random",
                slot,
                value: "",
                createdAt: Date.now(),
            });

            await load();
        } catch (err) {
            recoverFromWriteError("add random generator", err);
        }
    }

    function setLocation(id, locationId) {
        setEls((previous) =>
            previous.map((item) =>
                item.id === id
                    ? { ...item, locationId }
                    : item
            )
        );

        elements
            .update(id, { locationId })
            .catch((err) =>
                recoverFromWriteError("change location", err)
            );
    }

    async function add(type) {
        const trimmed = drafts[type].trim();
        const count = els.filter(
            (element) => element.type === type
        ).length;

        const name =
            trimmed || `${TYPES[type].label} ${count + 1}`;

        const counters = {};

        TYPES[type].counters.forEach((counter) => {
            counters[counter.key] = 0;
        });

        try {
            setError("");

            await elements.create({
                type,
                name,
                counters,
                locationId: "",
                createdAt: Date.now(),
            });

            setDrafts((previous) => ({
                ...previous,
                [type]: "",
            }));

            await load();
        } catch (err) {
            recoverFromWriteError(`add ${TYPES[type].label.toLowerCase()}`, err);
        }
    }

    function requestRemove(id) {
        const element = els.find((item) => item.id === id);

        if (element) {
            setPendingRemoval(element);
        }
    }

    function confirmRemove() {
        const id = pendingRemoval?.id;

        if (!id) {
            return;
        }

        setPendingRemoval(null);

        // Remove immediately from the interface.
        setEls((previous) =>
            previous.filter((element) => element.id !== id)
        );

        elements
            .remove(id)
            .catch((err) =>
                recoverFromWriteError("delete element", err)
            );
    }

    if (!loaded) {
        return (
            <div
                style={{
                    fontFamily: "system-ui",
                    color: C.muted,
                    padding: 16,
                }}
            >
                Loading…
            </div>
        );
    }

    const scenario = els.find(
        (element) => element.type === "scenario"
    );

    const locations = els.filter(
        (element) => element.type === "location"
    );

    const enemies = els.filter(
        (element) => element.type === "enemy"
    );

    const players = els.filter(
        (element) => element.type === "player"
    );

    const randoms = els
        .filter((element) => element.type === "random")
        .sort(
            (a, b) =>
                (Number.isFinite(a.slot) ? a.slot : 0) -
                (Number.isFinite(b.slot) ? b.slot : 0)
        );

    const doomInPlay =
        (scenario?.counters?.doom ?? 0) +
        enemies.reduce(
            (total, enemy) =>
                total + (enemy.counters?.doom ?? 0),
            0
        );

    const cardsFor = (list) =>
        list.map((element) => (
            <ElementCard
                key={element.id}
                el={element}
                type={TYPES[element.type]}
                locations={locations}
                onDelta={(key, amount) =>
                    delta(element.id, key, amount)
                }
                onLocation={(locationId) =>
                    setLocation(element.id, locationId)
                }
                onRemove={() => requestRemove(element.id)}
            />
        ));

    return (
        <div
            style={{
                fontFamily: "system-ui",
                color: C.text,
                minHeight: "100%",
                padding: 7,
            }}
        >
            <DeleteDialog
                element={pendingRemoval}
                onCancel={() => setPendingRemoval(null)}
                onConfirm={confirmRemove}
            />

            {error && (
                <div
                    role="alert"
                    style={{
                        marginBottom: 14,
                        padding: "10px 12px",
                        borderRadius: 8,
                        border: "1px solid #e5484d66",
                        background: "#e5484d18",
                        color: "#ff9b9f",
                        fontSize: 13,
                    }}
                >
                    {error}
                </div>
            )}

            <Section title="Scenario">
                {scenario && (
                    <ElementCard
                        el={scenario}
                        type={TYPES.scenario}
                        locations={locations}
                        onDelta={(key, amount) =>
                            delta(scenario.id, key, amount)
                        }
                        onLocation={() => {}}
                        onRemove={null}
                    />
                )}

                <div
                    style={{
                        fontSize: 13,
                        color: C.muted,
                        paddingLeft: 2,
                    }}
                >
                    Total doom in play:{" "}
                    <strong style={{ color: COLORS.doom }}>
                        {doomInPlay}
                    </strong>
                </div>
            </Section>

            <Section title="Random">
                {randoms.map((random) => (
                    <RandomGen
                        key={random.id}
                        value={random.value ?? ""}
                        onChange={(value) =>
                            setRandomValue(random.id, value)
                        }
                        onRemove={() => requestRemove(random.id)}
                    />
                ))}

                <button
                    type="button"
                    onClick={addRandom}
                    style={addBtn}
                >
                    Add generator
                </button>
            </Section>

            <Section title="Investigators">
                <AddRow
                    type="player"
                    value={drafts.player}
                    onChange={(value) =>
                        setDrafts((previous) => ({
                            ...previous,
                            player: value,
                        }))
                    }
                    onAdd={() => add("player")}
                />

                {cardsFor(players)}
            </Section>

            <Section title="Enemies">
                <AddRow
                    type="enemy"
                    value={drafts.enemy}
                    onChange={(value) =>
                        setDrafts((previous) => ({
                            ...previous,
                            enemy: value,
                        }))
                    }
                    onAdd={() => add("enemy")}
                />

                {cardsFor(enemies)}
            </Section>

            <Section title="Locations">
                <AddRow
                    type="location"
                    value={drafts.location}
                    onChange={(value) =>
                        setDrafts((previous) => ({
                            ...previous,
                            location: value,
                        }))
                    }
                    onAdd={() => add("location")}
                />

                {cardsFor(locations)}
            </Section>
        </div>
    );
}

// @miniapp-storage
const STORAGE = {
    "__collections" : {
        "arkhamElements" : [
            {
                "counters" : {
                    "act" : 1,
                    "agenda" : 1,
                    "doom" : 0
                },
                "createdAt" : 1782980198263,
                "id" : "F7D84010-BCF6-410D-94BC-0516BDB29A3A",
                "name" : "Scenario",
                "type" : "scenario"
            },
            {
                "createdAt" : 1782980211153,
                "id" : "73CFA012-1FEE-495F-8BEC-53F950C72588",
                "slot" : 0,
                "type" : "random",
                "value" : "3: 0..99"
            },
            {
                "createdAt" : 1782980246346,
                "id" : "221316DC-30BE-4D68-B59E-3F57AE90EB6E",
                "slot" : 1,
                "type" : "random",
                "value" : "5: 💀💀👤🧩🫀🦑⭐➕0112334"
            }
        ]
    }
};
