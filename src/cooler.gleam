import gleam/float
import gleam/int
import gleam/list
import gleam/regexp
import gleam/string
import lustre
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/event

// MODEL
pub type Model {
  Model(palette: List(ColorBar))
}

pub type ColorBar {
  ColorBar(hex: String, locked: Bool)
}

pub type TextColor {
  Light
  Dark
}

// MAIN
pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

pub fn init(_flags) -> #(Model, Effect(Msg)) {
  let url_hash = do_get_url_hash()
  let palette = case string.length(url_hash) > 0 {
    True -> {
      let decoded = decode_url_to_palette(url_hash)
      case list.is_empty(decoded) {
        True -> generate_initial_palette(5)
        False -> decoded
      }
    }
    False -> generate_initial_palette(5)
  }

  let key_listener = setup_key_listener(RegenerateUnlocked)
  let hash_listener = setup_hash_listener()

  #(Model(palette: palette), effect.batch([key_listener, hash_listener]))
}

// FFI
@external(javascript, "./cooler_ffi.mjs", "addKeyListener")
fn do_add_key_listener(callback: fn() -> Nil) -> Nil

fn setup_key_listener(msg: Msg) -> Effect(Msg) {
  effect.from(fn(dispatch) { do_add_key_listener(fn() { dispatch(msg) }) })
}

@external(javascript, "./cooler_ffi.mjs", "copyToClipboard")
fn do_copy_to_clipboard(text: String) -> Nil

fn copy_to_clipboard(text: String) -> Effect(Msg) {
  effect.from(fn(_) { do_copy_to_clipboard(text) })
}

@external(javascript, "./cooler_ffi.mjs", "updateUrlHash")
fn do_update_url_hash(hash: String) -> Nil

fn update_url(palette: List(ColorBar)) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    let encoded = encode_palette_to_url(palette)
    do_update_url_hash(encoded)
  })
}

@external(javascript, "./cooler_ffi.mjs", "getUrlHash")
fn do_get_url_hash() -> String

@external(javascript, "./cooler_ffi.mjs", "onHashChange")
fn do_on_hash_change(callback: fn(String) -> Nil) -> Nil

fn setup_hash_listener() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    do_on_hash_change(fn(hash) { dispatch(LoadFromUrl(hash)) })
  })
}

// UPDATE
pub type Msg {
  ToggleLock(index: Int)
  RegenerateUnlocked
  UpdateHex(index: Int, hex: String)
  CopyHex(hex: String)
  AddColorAfter(index: Int)
  RemoveColor(index: Int)
  // UpdateUrl
  LoadFromUrl(String)
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ToggleLock(index) -> {
      let new_palette = toggle_lock_at(model.palette, index)
      #(Model(palette: new_palette), update_url(new_palette))
    }
    RegenerateUnlocked -> {
      let new_palette = regenerate_unlocked(model.palette)
      #(Model(palette: new_palette), update_url(new_palette))
    }
    UpdateHex(index, hex) -> {
      let new_palette = update_hex_at(model.palette, index, hex)
      #(Model(palette: new_palette), update_url(new_palette))
    }
    CopyHex(hex) -> {
      #(model, copy_to_clipboard(hex))
    }
    AddColorAfter(index) -> {
      let new_palette = add_color_after(model.palette, index)
      #(Model(palette: new_palette), update_url(new_palette))
    }
    RemoveColor(index) -> {
      case list.length(model.palette) > 2 {
        True -> {
          let new_palette = remove_color_at(model.palette, index)
          #(Model(palette: new_palette), update_url(new_palette))
        }
        False -> #(model, effect.none())
      }
    }
    LoadFromUrl(hash) -> {
      let decoded = decode_url_to_palette(hash)
      case list.is_empty(decoded) {
        True -> #(model, effect.none())
        False -> #(Model(palette: decoded), effect.none())
      }
    }
  }
}

// VIEW
pub fn view(model: Model) -> Element(Msg) {
  let palette_count = list.length(model.palette)

  h.div([], [
    h.div(
      [
        attr.class(
          "flex relative w-full h-full bg-gray-200 items-end justify-between pb-2",
        ),
      ],
      [
        h.h1(
          [
            attr.class(
              "text-6xl mt-6 font-bold font-heading text-primary text-center ml-4",
            ),
          ],
          [
            h.text("Cooler"),
          ],
        ),
        h.div([attr.class("flex flex-col mr-4")], [
          h.p([attr.class("text-center text-lg text-gray-800 mt-2 font-body")], [
            h.text("A simple color palette generator"),
          ]),
          h.p([attr.class("text-center text-sm text-gray-800 mt-1 font-body")], [
            h.text("Press "),
            h.span([attr.class("font-mono")], [h.text("space")]),
            h.text(" to regenerate unlocked colors"),
          ]),
        ]),
      ],
    ),
    h.div(
      [
        attr.class("flex flex-row absolute h-full w-full"),
      ],
      list.index_map(model.palette, fn(bar, index) {
        color_bar_view(bar, index, palette_count)
      }),
    ),
  ])
}

fn color_bar_view(bar: ColorBar, index: Int, total: Int) -> Element(Msg) {
  let text_color = get_text_color(bar.hex)
  let assert Ok(_re) = regexp.from_string("^#([0-9a-fA-F]{6})$")
  let is_last = index == total - 1

  h.div([attr.class("flex flex-row relative h-full w-full")], [
    case index == 0 {
      True ->
        h.div(
          [
            attr.class(
              "absolute content-center left-0 top-0 bottom-0 mr-[20px] z-2 group",
            ),
          ],
          [
            h.button(
              [
                attr.class(
                  "flex bg-white items-center justify-center w-[40px] h-[40px] text-black
                   px-4 py-2 rounded-full shadow-md transition invisible group-hover:visible
                   cursor-pointer group-hover:scale-125 active:scale-85",
                ),
                attr.type_("button"),
                event.on_click(AddColorAfter(-1)),
                attr.attribute("onmouseup", "this.blur()"),
              ],
              [h.i([attr.class("iconoir-plus text-xl")], [])],
            ),
          ],
        )
      False -> h.div([], [])
    },
    h.div(
      [
        attr.class(
          "min-w-full w-full min-h-full h-full flex flex-col justify-end pb-32",
        ),
        case text_color {
          Light -> attr.class("text-white")
          Dark -> attr.class("text-black")
        },
        attr.styles([#("background-color", bar.hex)]),
      ],
      [
        h.div([attr.class("font-heading text-2xl text-center font-bold")], [
          h.input([
            attr.class(
              "mt-4 text-center w-32 bg-transparent border-b-2 focus:outline-none",
            ),
            attr.type_("text"),
            attr.value(bar.hex),
            case text_color {
              Light -> attr.class("text-white placeholder-white border-white")
              Dark -> attr.class("text-black placeholder-black border-black")
            },
            event.on_input(fn(value) { UpdateHex(index, value) }),
            attr.attribute("maxlength", "7"),
          ]),
        ]),
        h.button(
          [
            attr.class(
              "w-full text-center flex content-center justify-center mt-4 cursor-pointer",
            ),
            attr.type_("button"),
            event.on_click(ToggleLock(index)),
            attr.attribute("onmouseup", "this.blur()"),
          ],
          [
            case bar.locked {
              True ->
                h.i(
                  [
                    attr.class(
                      "iconoir-lock text-4xl transition hover:scale-110 active:scale-85",
                    ),
                  ],
                  [],
                )
              False ->
                h.i(
                  [
                    attr.class(
                      "iconoir-lock-slash text-4xl transition hover:scale-110 active:scale-85",
                    ),
                  ],
                  [],
                )
            },
          ],
        ),
        h.button(
          [
            attr.class(
              "w-full text-center flex content-center justify-center mt-4 cursor-pointer",
            ),
            attr.type_("button"),
            event.on_click(CopyHex(bar.hex)),
            attr.attribute("onmouseup", "this.blur()"),
          ],
          [
            h.i(
              [
                attr.class(
                  "iconoir-copy text-4xl transition hover:scale-110 active:scale-85",
                ),
              ],
              [],
            ),
          ],
        ),
        h.button(
          [
            attr.class(
              "w-full text-center flex content-center justify-center mt-4 cursor-pointer",
            ),
            attr.type_("button"),
            event.on_click(RemoveColor(index)),
            attr.attribute("onmouseup", "this.blur()"),
          ],
          [
            h.i(
              [
                attr.class(
                  "iconoir-trash text-4xl transition hover:scale-110 active:scale-85",
                ),
              ],
              [],
            ),
          ],
        ),
      ],
    ),
    h.div(
      [
        attr.class(case is_last {
          True ->
            "absolute content-center right-0 top-0 bottom-0 mr-0 z-2 group"
          False ->
            "absolute content-center right-0 top-0 bottom-0 mr-[-20px] z-2 group"
        }),
      ],
      [
        h.button(
          [
            attr.class(
              "flex bg-white items-center justify-center w-[40px] h-[40px] text-black
              px-4 py-2 rounded-full shadow-md transition invisible group-hover:visible
              cursor-pointer group-hover:scale-125 active:scale-85",
            ),
            attr.type_("button"),
            event.on_click(AddColorAfter(index)),
            attr.attribute("onmouseup", "this.blur()"),
          ],
          [
            h.i([attr.class("iconoir-plus text-xl")], []),
          ],
        ),
      ],
    ),
  ])
}

// HELPERS
fn generate_palette(existing: List(ColorBar)) -> List(ColorBar) {
  list.map(existing, fn(bar) {
    case bar.locked {
      True -> bar
      False -> ColorBar(hex: random_color(), locked: False)
    }
  })
}

fn generate_initial_palette(count: Int) -> List(ColorBar) {
  list.range(0, count - 1)
  |> list.map(fn(_) { ColorBar(hex: random_color(), locked: False) })
}

fn regenerate_unlocked(palette: List(ColorBar)) -> List(ColorBar) {
  generate_palette(palette)
}

fn toggle_lock_at(palette: List(ColorBar), index: Int) -> List(ColorBar) {
  list.index_map(palette, fn(bar, i) {
    case i == index {
      True -> ColorBar(..bar, locked: !bar.locked)
      False -> bar
    }
  })
}

fn update_hex_at(
  palette: List(ColorBar),
  index: Int,
  hex: String,
) -> List(ColorBar) {
  let updated_hex = case string.contains(hex, "#") {
    False -> "#" <> hex
    True -> hex
  }

  list.index_map(palette, fn(bar, i) {
    case i == index {
      True -> ColorBar(..bar, hex: updated_hex)
      False -> bar
    }
  })
}

fn add_color_after(palette: List(ColorBar), index: Int) -> List(ColorBar) {
  case index {
    -1 -> {
      case list.first(palette) {
        Ok(_first) -> [ColorBar(hex: random_color(), locked: False), ..palette]
        Error(_) -> palette
      }
    }
    _ -> {
      let before = list.take(palette, index + 1)
      let after = list.drop(palette, index + 1)

      let new_hex = case list.last(before), list.first(after) {
        Ok(left), Ok(right) -> average_colors(left.hex, right.hex)
        Ok(_left), Error(_) -> random_color()
        _, _ -> random_color()
      }

      list.append(before, [ColorBar(hex: new_hex, locked: False), ..after])
    }
  }
}

fn remove_color_at(palette: List(ColorBar), index: Int) -> List(ColorBar) {
  palette
  |> list.index_map(fn(bar, i) { #(bar, i) })
  |> list.filter(fn(pair) { pair.1 != index })
  |> list.map(fn(pair) { pair.0 })
}

fn encode_palette_to_url(palette: List(ColorBar)) -> String {
  palette
  |> list.map(fn(bar) {
    let hex_clean = string.replace(bar.hex, "#", "")
    let locked_flag = case bar.locked {
      True -> "1"
      False -> "0"
    }
    hex_clean <> "-" <> locked_flag
  })
  |> string.join(",")
}

fn decode_url_to_palette(hash: String) -> List(ColorBar) {
  string.split(hash, ",")
  |> list.filter_map(fn(segment) {
    case string.split(segment, "-") {
      [hex, locked_str] -> {
        let locked = locked_str == "1"
        Ok(ColorBar(hex: "#" <> hex, locked: locked))
      }
      _ -> Error(Nil)
    }
  })
}

fn random_color() -> String {
  // Hue: 0-360
  let h = int.random(360)

  // Saturation: 60-90%
  let s = int.random(30) + 60

  // Lightness: 45-65%
  let l = int.random(20) + 45

  hsl_to_hex(h, s, l)
}

fn hsl_to_hex(h: Int, s: Int, l: Int) -> String {
  // convert percentages to decimals
  let s_decimal = int.to_float(s) /. 100.0
  let l_decimal = int.to_float(l) /. 100.0

  // calculate RGB values
  let c = { 1.0 -. float.absolute_value(2.0 *. l_decimal -. 1.0) } *. s_decimal
  let h_prime = int.to_float(h) /. 60.0
  let assert Ok(h_mod) = float.modulo(h_prime, 2.0)
  let x = c *. { 1.0 -. float.absolute_value(h_mod -. 1.0) }
  let m = l_decimal -. c /. 2.0

  let #(r_prime, g_prime, b_prime) = case h_prime <. 1.0 {
    True -> #(c, x, 0.0)
    False ->
      case h_prime <. 2.0 {
        True -> #(x, c, 0.0)
        False ->
          case h_prime <. 3.0 {
            True -> #(0.0, c, x)
            False ->
              case h_prime <. 4.0 {
                True -> #(0.0, x, c)
                False ->
                  case h_prime <. 5.0 {
                    True -> #(x, 0.0, c)
                    False -> #(c, 0.0, x)
                  }
              }
          }
      }
  }

  // Convert to 0-255 range
  let r = { r_prime +. m } *. 255.0 |> float.round
  let g = { g_prime +. m } *. 255.0 |> float.round
  let b = { b_prime +. m } *. 255.0 |> float.round

  "#" <> int_to_hex(r) <> int_to_hex(g) <> int_to_hex(b)
}

fn int_to_hex(n: Int) -> String {
  let hex = int.to_base16(n)
  case string.length(hex) {
    1 -> "0" <> hex
    _ -> hex
  }
}

fn get_text_color(hex: String) -> TextColor {
  let hex_clean = string.replace(hex, "#", "")

  // parse RGB values
  let assert Ok(r) = int.base_parse(string.slice(hex_clean, 0, 2), 16)
  let assert Ok(g) = int.base_parse(string.slice(hex_clean, 2, 2), 16)
  let assert Ok(b) = int.base_parse(string.slice(hex_clean, 4, 2), 16)

  // calculate relative luminance using the standard formula
  let luminance =
    0.299
    *. int.to_float(r)
    +. 0.587
    *. int.to_float(g)
    +. 0.114
    *. int.to_float(b)

  // if luminance is high (bright color), use dark text, if not, light text
  case luminance >. 128.0 {
    True -> Dark
    False -> Light
  }
}

fn average_colors(hex1: String, hex2: String) -> String {
  // parse both colors
  let clean1 = string.replace(hex1, "#", "")
  let clean2 = string.replace(hex2, "#", "")

  let assert Ok(r1) = int.base_parse(string.slice(clean1, 0, 2), 16)
  let assert Ok(g1) = int.base_parse(string.slice(clean1, 2, 2), 16)
  let assert Ok(b1) = int.base_parse(string.slice(clean1, 4, 2), 16)

  let assert Ok(r2) = int.base_parse(string.slice(clean2, 0, 2), 16)
  let assert Ok(g2) = int.base_parse(string.slice(clean2, 2, 2), 16)
  let assert Ok(b2) = int.base_parse(string.slice(clean2, 4, 2), 16)

  // Average them
  let r = { r1 + r2 } / 2
  let g = { g1 + g2 } / 2
  let b = { b1 + b2 } / 2

  "#" <> int_to_hex(r) <> int_to_hex(g) <> int_to_hex(b)
}
