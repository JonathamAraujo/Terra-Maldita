extends RefCounted
## Falas dos NPCs e da história. Formato: "Falante|texto". Edite à vontade.

const INTRO_CARDS := [
	"SERTÃO, 1897.\n\nO Coronel Cascavel e seu bando dominam estas terras. Roubam o gado, queimaram o povoado velho e secaram o poço de Santa Rita.",
	"A cabeça do Coronel tem preço.\nMas, para você, caçador, isso é pessoal: foi o bando dele que levou tudo o que você tinha.",
	"Atravesse o sertão. Enfrente bandidos e capangas.\nEncontre armas melhores. Chegue ao esconderijo.\n\nDerrote o Coronel Cascavel.",
]

const NPC := {
	"tobias": [
		"Tobias|Você deve ser o caçador de recompensas. Seja bem-vindo a Terra Maldita.",
		"Tobias|Ouça: o Coronel Cascavel e o bando dele mandam daqui até as serras. Secaram o poço, roubaram o gado e queimaram o povoado velho.",
		"Tobias|Mire com o MOUSE, atire com o botão ESQUERDO e recarregue com R. Aperte E para abrir baús e falar com o povo.",
		"Tobias|Treine nos alvos ali por perto e siga a estrada para a vila. Que Deus te guarde.",
	],
	"maria": [
		"Maria|O Coronel levou meu marido e secou o poço da vila. Quem reclama, a capangada resolve.",
		"Maria|Se você derrubar aquele homem, Santa Rita volta a ter água. Por favor, volte vivo.",
	],
	"ze": [
		"Zé|Tem um baú na saída da vila com um revólver de respeito. Pistola velha não aguenta a capangada, não.",
		"Zé|E dizem que no fim da estrada, lá pra esquerda, tem um canto que nem os bandidos conhecem.",
	],
	"padre": [
		"Padre Antônio|Deus perdoa, filho, mas o Coronel Cascavel nunca perdoou ninguém.",
		"Padre Antônio|O esconderijo dele fica depois do acampamento e da terra dos capangas. Beba água do poço antes de partir.",
	],
	"luzia": [
		"Luzia|Meu irmão virou capanga dele. Se encontrar, diga que a mãe pergunta dele.",
		"Luzia|Capanga é durão, aguenta muito chumbo. A espingarda resolve, mas só de perto.",
	],
	"chico": [
		"Chico|Cuidado com o bode ali. Já derrubou um soldado inteiro.",
		"Chico|Teve um cabra que jurou ter visto até Lampião por essas bandas. Mentira de sertanejo... mas eu acredito.",
	],
	"cruz": [
		"Cruz de madeira|Aqui descansa Jumento, fiel companheiro do Coronel.",
		"Cruz de madeira|Morreu de tanto carregar a maldade do dono. (Você achou um segredo!)",
	],
}

const BOSS_INTRO := [
	"Coronel Cascavel|Então é você o caçador que andou deixando meu povo estendido pela estrada.",
	"Coronel Cascavel|Esse sertão é meu. A água é minha. A lei sou eu. Daqui você não sai.",
]

const WIN_TEXT := "O Coronel Cascavel caiu.\nA água volta a correr em Santa Rita,\ne o sertão respira outra vez."
