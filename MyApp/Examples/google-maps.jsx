// @name Google Maps
// @type react
// @icon 🗺️

// Globals: React, db
//
// A minimal Google Maps mini-app: shows a full-screen map and lets you search
// for a place. Selecting a search result drops a marker and flies there; you
// can save places to a favourites list (persisted through the `db` bridge) and
// tap one to fly back.
//
// Google Maps needs an API key. This app asks for one on first run and stores
// it as the single row of the `db` "config" collection. Create a key in the
// Google Cloud console with the "Maps JavaScript API" and "Places API" enabled.
// The web view's origin is https://miniapp.local/, so if you add an HTTP-referrer
// restriction to the key, allow that origin — or leave the key unrestricted for
// testing.

const { useState, useEffect, useRef, useCallback } = React;

const config = db.collection("config");
const places = db.collection("places");
const DEFAULT_CENTER = { lat: 40.416775, lng: -3.70379 }; // Madrid
const DEFAULT_ZOOM = 12;

// Loads the Google Maps JS API exactly once and resolves when the API *and*
// the requested libraries are actually ready. Repeated calls return the same
// in-flight/settled promise so the script tag is never injected twice.
//
// We resolve from the API's `callback`, not the script tag's `onload`: with the
// async loader the script downloads a tiny bootstrapper and `onload` fires
// before `google.maps.Map` exists. The `callback` fires only once `maps` and
// `places` are loaded, so `new google.maps.Map(...)` is safe by then.
let mapsPromise = null;
function loadGoogleMaps(apiKey) {
  if (mapsPromise) return mapsPromise;
  mapsPromise = new Promise((resolve, reject) => {
    window.__onGoogleMapsReady = () => resolve(window.google);
    const script = document.createElement("script");
    const key = encodeURIComponent(apiKey);
    script.src =
      `https://maps.googleapis.com/maps/api/js?key=${key}` +
      `&libraries=places&loading=async&callback=__onGoogleMapsReady`;
    script.async = true;
    script.onerror = () => {
      mapsPromise = null; // allow a retry after a bad key / network error
      reject(new Error("Failed to load the Google Maps script."));
    };
    document.head.appendChild(script);
  });
  return mapsPromise;
}

// First-run screen: collect and persist the Google Maps API key.
function ApiKeyGate({ onSaved }) {
  const [value, setValue] = useState("");

  async function save(e) {
    e.preventDefault();
    const key = value.trim();
    if (!key) return;
    // `config` holds a single row; update it if present, otherwise create it.
    const [cfg] = await config.list();
    if (cfg) await config.update(cfg.id, { apiKey: key });
    else await config.create({ apiKey: key });
    onSaved(key);
  }

  return (
    <div className="gate">
      <h1>🗺️ Google Maps</h1>
      <p className="muted">
        Paste a Google Maps API key. It needs the <b>Maps JavaScript API</b>
        and <b>Places API</b> enabled, billing turned on for the project, and the key
        allowed to call both (no API restriction that blocks them). If you add an
        HTTP-referrer restriction, allow <code>https://miniapp.local/*</code>.
      </p>
      <form className="row" onSubmit={save}>
        <input
          type="text"
          placeholder="AIza…"
          value={value}
          onChange={(e) => setValue(e.target.value)}
        />
        <button type="submit">Save</button>
      </form>
    </div>
  );
}

// The map itself, once we have a key. Holds the live `google.maps.Map` and a
// single marker in refs (they live outside React's render cycle).
function MapView({ apiKey, onResetKey }) {
  const mapEl = useRef(null);
  const inputEl = useRef(null);
  const mapRef = useRef(null);
  const markerRef = useRef(null);

  const [status, setStatus] = useState("loading"); // loading | ready | error
  const [error, setError] = useState("");
  const [current, setCurrent] = useState(null); // the place shown right now
  const [favourites, setFavourites] = useState([]);

  const refreshFavourites = useCallback(async () => {
    setFavourites(await places.list({ orderBy: "createdAt", desc: true }));
  }, []);

  // Move the map + marker to a location and remember what's shown.
  const goTo = useCallback((place) => {
    const map = mapRef.current;
    if (!map) return;
    const pos = { lat: place.lat, lng: place.lng };
    map.panTo(pos);
    map.setZoom(15);
    markerRef.current.setPosition(pos);
    markerRef.current.setVisible(true);
    setCurrent(place);
  }, []);

  // Boot the map once. Loads the API, creates the map + marker, and wires the
  // Places Autocomplete to the search input.
  useEffect(() => {
    let cancelled = false;
    loadGoogleMaps(apiKey)
      .then((google) => {
        if (cancelled) return;
        const map = new google.maps.Map(mapEl.current, {
          center: DEFAULT_CENTER,
          zoom: DEFAULT_ZOOM,
          disableDefaultUI: true,
          zoomControl: true,
          clickableIcons: false,
        });
        mapRef.current = map;
        markerRef.current = new google.maps.Marker({ map, visible: false });

        const ac = new google.maps.places.Autocomplete(inputEl.current, {
          fields: ["geometry", "name", "formatted_address"],
        });
        ac.addListener("place_changed", () => {
          const p = ac.getPlace();
          if (!p.geometry || !p.geometry.location) return;
          goTo({
            name: p.name || p.formatted_address || "Dropped pin",
            address: p.formatted_address || "",
            lat: p.geometry.location.lat(),
            lng: p.geometry.location.lng(),
          });
        });

        setStatus("ready");
      })
      .catch((err) => {
        if (cancelled) return;
        setError(err.message || String(err));
        setStatus("error");
      });
    return () => {
      cancelled = true;
    };
  }, [apiKey, goTo]);

  useEffect(() => {
    refreshFavourites();
  }, [refreshFavourites]);

  async function saveCurrent() {
    if (!current) return;
    await places.create({ ...current, createdAt: Date.now() });
    refreshFavourites();
  }

  async function removeFavourite(fav, e) {
    e.stopPropagation();
    await places.remove(fav.id);
    refreshFavourites();
  }

  const alreadySaved =
    current &&
    favourites.some(
      (f) => f.lat === current.lat && f.lng === current.lng
    );

  return (
    <div className="app">
      <div className="bar">
        <input
          ref={inputEl}
          type="text"
          placeholder="Search for a place…"
          disabled={status !== "ready"}
        />
        <button className="ghost" onClick={onResetKey} title="Change API key">
          🔑
        </button>
      </div>

      <div className="map-wrap">
        <div ref={mapEl} className="map" />

        {status === "loading" && (
          <div className="overlay muted">Loading map…</div>
        )}
        {status === "error" && (
          <div className="overlay error">
            <p>Couldn’t load the map.</p>
            <p className="small">{error}</p>
            <button onClick={onResetKey}>Change API key</button>
          </div>
        )}

        {status === "ready" && current && (
          <div className="card">
            <div className="card-text">
              <b>{current.name}</b>
              {current.address ? <div className="small">{current.address}</div> : null}
            </div>
            <button onClick={saveCurrent} disabled={alreadySaved}>
              {alreadySaved ? "Saved" : "★ Save"}
            </button>
          </div>
        )}
      </div>

      {favourites.length > 0 && (
        <div className="favs">
          <div className="favs-title">Saved places</div>
          <ul>
            {favourites.map((f) => (
              <li key={f.id} onClick={() => goTo(f)}>
                <span className="fav-name">{f.name}</span>
                <button className="del" onClick={(e) => removeFavourite(f, e)}>
                  ✕
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

// Shared stylesheet for every screen. Rendered once at the App level (not inside
// a single screen) so the gate, loading, and map views are all styled — a
// `<style>` scoped to one component wouldn't apply to the others.
function Styles() {
  return (
    <style>{`
      html, body { height: 100%; }
      body { padding: 0; }
      .app { position: fixed; inset: 0; display: flex; flex-direction: column; }
      .bar { display: flex; gap: 8px; padding: 10px; }
      .bar input {
        flex: 1; padding: 11px 12px; font-size: 16px;
        border: 1px solid #8884; border-radius: 12px; background: #8881; color: inherit;
      }
      button {
        padding: 11px 14px; font-size: 16px; border: 0; border-radius: 12px;
        background: #007aff; color: #fff; cursor: pointer;
      }
      button:disabled { opacity: 0.5; }
      button.ghost { background: #8882; color: inherit; }
      .map-wrap { position: relative; flex: 1; }
      .map { position: absolute; inset: 0; }
      .overlay {
        position: absolute; inset: 0; display: flex; flex-direction: column;
        align-items: center; justify-content: center; gap: 10px; text-align: center;
        padding: 24px; background: #80808022;
      }
      .card {
        position: absolute; left: 12px; right: 12px; bottom: 12px;
        display: flex; align-items: center; gap: 10px;
        padding: 12px 14px; border-radius: 14px;
        background: Canvas; color: CanvasText;
        box-shadow: 0 6px 24px #0005;
      }
      .card-text { flex: 1; min-width: 0; }
      .card-text b { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .favs { max-height: 34vh; overflow-y: auto; padding: 6px 10px 10px; }
      .favs-title { font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.04em; opacity: 0.5; margin: 6px 4px; }
      .favs ul { list-style: none; padding: 0; margin: 0; }
      .favs li {
        display: flex; align-items: center; gap: 10px; padding: 12px 8px;
        border-bottom: 1px solid #8883; cursor: pointer;
      }
      .fav-name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .del { background: transparent; color: #ff3b30; padding: 4px 8px; }
      .gate { padding: 24px; font-size: 16px; }
      .muted { opacity: 0.6; }
      .small { font-size: 0.85rem; opacity: 0.7; }
      .error { color: #ff3b30; }
      .row { display: flex; gap: 8px; margin-top: 14px; }
      .row input { flex: 1; padding: 11px 12px; font-size: 16px; border: 1px solid #8884; border-radius: 12px; background: #8881; color: inherit; }
    `}</style>
  );
}

function App() {
  const [apiKey, setApiKey] = useState(null);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    config.list().then((rows) => {
      if (rows[0] && rows[0].apiKey) setApiKey(rows[0].apiKey);
      setLoaded(true);
    });
  }, []);

  // One screen at a time, but Styles is always mounted so every screen is styled.
  let screen;
  if (!loaded) screen = <p className="muted" style={{ padding: 24 }}>Loading…</p>;
  else if (!apiKey) screen = <ApiKeyGate onSaved={setApiKey} />;
  else screen = <MapView apiKey={apiKey} onResetKey={() => setApiKey(null)} />;

  return (
    <>
      <Styles />
      {screen}
    </>
  );
}
