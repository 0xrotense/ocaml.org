---
packages:
- name: hl_yaml
  tested_version: 1.0.0
  used_libraries:
  - hl_yaml
- name: ppx_deriving_yojson
  tested_version: 3.7.0
  used_libraries:
  - ppx_deriving_yojson
---
(* This is the string we are deserializing into the types we define below. *)
let yaml = {|
french name: pâte sucrée
ingredients:
- name: flour
  weight: 250
- name: butter
  weight: 100
- name: sugar
  weight: 100
- name: egg
  weight: 50
- name: salt
  weight: 5
steps:
- soften butter
- add sugar
- add egg and salt
- add flour
|}

(* The `[@@deriving of_yojson]` attribute makes the ppx from the library `ppx_deriving_yojson` generate the function
  `ingredient_of_yojson : Yojson.Safe.t -> (ingredient, string) result`.
  If both serialising and deserialising are needed, replace `of_yojson` by `yojson`. *)
type ingredient = {
  name: string;
  weight: int;
} [@@deriving of_yojson]

(* The function ``recipe_of_yojson : Yojson.Safe.t -> (ingredient, string) result`` generated here internally uses
  `ingredient_of_yojson`. *)
type recipe = {
  name: string; [@key "french name"]
  ingredients: ingredient list;
  steps: string list;
} [@@deriving of_yojson]

(* `parse` takes a function that converts from `Yojson.Safe.t` into the desired record type as an argument. *)
let pate_sucree =
  yaml
  |> Hl_yaml.Unix.parse ~of_yojson:recipe_of_yojson
