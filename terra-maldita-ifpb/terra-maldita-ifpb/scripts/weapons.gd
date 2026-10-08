extends RefCounted
## Banco de dados de armas. Para criar uma arma nova, adicione uma entrada em DATA e em ORDER.
## Uso: const Weapons = preload("res://scripts/weapons.gd")  ->  Weapons.get_data("pistola")
##
## name          : nome exibido
## damage        : dano por projétil
## fire_rate     : segundos entre tiros
## max_range     : alcance em pixels
## bullet_speed  : velocidade do projétil
## mag           : tamanho do pente
## reload        : tempo de recarga (s)
## pellets       : projéteis por tiro (espingarda > 1)
## spread        : dispersão em radianos
## auto          : true = segurar o botão dispara continuamente
## shake         : força do tremor de câmera
## start_reserve : munição reserva ao pegar a arma (-1 = infinita)
## ammo_pack     : munição reserva ganha por pacote
## max_reserve   : limite de munição reserva (-1 = sem limite)
## icon          : região do ícone em Assets/09_armas_itens.png
## tip           : dica mostrada ao pegar a arma

const ICON_SHEET := "res://Assets/09_armas_itens.png"

## Ordem dos slots (teclas 1-4).
const ORDER: Array[String] = ["pistola", "revolver", "espingarda", "rifle"]

const DATA := {
	"pistola": {
		"name": "Pistola Velha",
		"damage": 1.0, "fire_rate": 0.35, "max_range": 170.0, "bullet_speed": 320.0,
		"mag": 6, "reload": 1.1, "pellets": 1, "spread": 0.02, "auto": false, "shake": 1.0,
		"start_reserve": -1, "ammo_pack": 0, "max_reserve": -1,
		"icon": Rect2(54, 28, 30, 19),
		"tip": "Fiel, mas fraca.",
	},
	"revolver": {
		"name": "Revólver Cangaceiro",
		"damage": 2.0, "fire_rate": 0.42, "max_range": 200.0, "bullet_speed": 360.0,
		"mag": 6, "reload": 1.3, "pellets": 1, "spread": 0.03, "auto": false, "shake": 1.6,
		"start_reserve": 12, "ammo_pack": 12, "max_reserve": 48,
		"icon": Rect2(54, 1, 35, 20),
		"tip": "Dano dobro da pistola.",
	},
	"espingarda": {
		"name": "Espingarda de Cano Duplo",
		"damage": 1.0, "fire_rate": 0.85, "max_range": 105.0, "bullet_speed": 300.0,
		"mag": 2, "reload": 1.7, "pellets": 6, "spread": 0.16, "auto": false, "shake": 3.0,
		"start_reserve": 8, "ammo_pack": 6, "max_reserve": 24,
		"icon": Rect2(0, 48, 48, 18),
		"tip": "Devastadora de perto.",
	},
	"rifle": {
		"name": "Rifle de Tocaia",
		"damage": 4.0, "fire_rate": 0.75, "max_range": 320.0, "bullet_speed": 480.0,
		"mag": 5, "reload": 1.9, "pellets": 1, "spread": 0.0, "auto": false, "shake": 2.2,
		"start_reserve": 10, "ammo_pack": 10, "max_reserve": 30,
		"icon": Rect2(0, 0, 48, 21),
		"tip": "Longo alcance, dano alto.",
	},
}

static func get_data(id: String) -> Dictionary:
	return DATA.get(id, DATA["pistola"])

static func icon_texture(id: String) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = load(ICON_SHEET)
	t.region = get_data(id)["icon"]
	return t
