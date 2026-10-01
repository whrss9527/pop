// 表情的数据（表情、分组、中文和英文的名字、关键词、肤色）来自 emojibase-data 17.0.0：
// https://github.com/milesj/emojibase ，许可证如下：
//
// MIT License
//
// Copyright (c) 2017-2019 Miles Johnson
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// 其中表情的名字和关键词来自 Unicode CLDR：https://cldr.unicode.org ，许可证如下：
//
// UNICODE LICENSE V3
//
// COPYRIGHT AND PERMISSION NOTICE
//
// Copyright © 2004-2026 Unicode, Inc.
//
// NOTICE TO USER: Carefully read the following legal agreement. BY
// DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
// SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
// TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
// DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of data files and any associated documentation (the "Data Files") or
// software and any associated documentation (the "Software") to deal in the
// Data Files or Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, and/or sell
// copies of the Data Files or Software, and to permit persons to whom the
// Data Files or Software are furnished to do so, provided that either (a)
// this copyright and permission notice appear with all copies of the Data
// Files or Software, or (b) this copyright and permission notice appear in
// associated Documentation.
//
// THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
// KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
// THIRD PARTY RIGHTS.
//
// IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
// BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
// OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
// WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
// ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
// FILES OR SOFTWARE.
//
// Except as contained in this notice, the name of a copyright holder shall
// not be used in advertising or otherwise to promote the sale, use or other
// dealings in these Data Files or Software without prior written
// authorization of the copyright holder.
//
// SPDX-License-Identifier: Unicode-3.0
//
// 这个文件是生成的：常用特殊符号的名字是 Pop 自己写的。

/// 表情和常用特殊符号的数据，用的时候再拆开（`EmojiSymbols`）
enum EmojiTable {
    /// 一行一个表情，按 Unicode 的顺序：表情、分组（0 笑脸、1 人物、3 动物、4 食物、5 旅行、6 活动、7 物品、8 符号、9 旗帜）、
    /// 是不是 Emoji 16.0 加的（macOS 15.4 起才有）、中文名、中文关键词、英文名、英文关键词、五种肤色（空格分开）。
    /// 用制表符分开，关键词之间用「|」
    static let emoji = """
    😀\t0\t0\t嘿嘿\t笑脸|脸|高兴\tgrinning face\tcheerful|cheery|face|grin|grinning|happy|laugh|nice|smile|smiling|teeth\t
    😃\t0\t0\t哈哈\t太棒了|开口笑|开口笑脸|笑脸|脸|高兴\tgrinning face with big eyes\tawesome|big|eyes|face|grin|grinning|happy|mouth|open|smile|smiling|teeth|yay\t
    😄\t0\t0\t大笑\t哈哈|开口而笑的脸|开心|笑|脸|露齿而笑|高兴\tgrinning face with smiling eyes\teye|eyes|face|grin|grinning|happy|laugh|lol|mouth|open|smile|smiling\t
    😁\t0\t0\t嘻嘻\t笑脸|笑颜|脸|露齿而笑\tbeaming face with smiling eyes\tbeaming|eye|eyes|face|grin|grinning|happy|nice|smile|smiling|teeth\t
    😆\t0\t0\t斜眼笑\tlol|咧嘴笑|哈哈|开心|眯眼|眯眼大笑|笑|脸|高兴\tgrinning squinting face\tclosed|eyes|face|grinning|haha|hahaha|happy|laugh|lol|mouth|open|rofl|smile|smiling|squinting\t
    😅\t0\t0\t苦笑\t冷汗|出汗|开口冒冷汗的脸|汗|泄气|紧张|脸\tgrinning face with sweat\tcold|dejected|excited|face|grinning|mouth|nervous|open|smile|smiling|stress|stressed|sweat\t
    🤣\t0\t0\t笑得满地打滚\tlolol|乐翻了|哈哈|地板|太扯了|打滚|满地打滚的笑|笑|笑得流泪|脸|超扯\trolling on the floor laughing\tcrying|face|floor|funny|haha|happy|hehe|hilarious|joy|laugh|lmao|lol|rofl|roflmao|rolling|tear\t
    😂\t0\t0\t笑哭了\tlol|喜极而泣|大笑|眼泪|笑|笑哭|脸\tface with tears of joy\tcrying|face|feels|funny|haha|happy|hehe|hilarious|joy|laugh|lmao|lol|rofl|roflmao|tear\t
    🙂\t0\t0\t呵呵\t开心|浅笑的脸|笑|脸\tslightly smiling face\tface|happy|slightly|smile|smiling\t
    🙃\t0\t0\t倒脸\t好玩|好笑|脸|颠倒|颠倒的脸\tupside-down face\tface|hehe|smile|upside-down\t
    🫠\t0\t0\t融化\t冷笑|哈哈|尴尬|微笑|消失|液体|溶解|热\tmelting face\tdisappear|dissolve|embarrassed|face|haha|heat|hot|liquid|lol|melt|melting|sarcasm|sarcastic\t
    😉\t0\t0\t眨眼\t媚眼|撩拨|眨眼的脸|笑|脸\twinking face\tface|flirt|heartbreaker|sexy|slide|tease|wink|winking|winks\t
    😊\t0\t0\t羞涩微笑\t害羞|微笑|满意|笑脸相迎|羞涩|脸|脸红\tsmiling face with smiling eyes\tblush|eye|eyes|face|glad|satisfied|smile|smiling\t
    😇\t0\t0\t微笑天使\t光环|天使|天真|幻想|微笑|脸|顶罩光环的笑脸\tsmiling face with halo\tangel|angelic|angels|blessed|face|fairy|fairytale|fantasy|halo|happy|innocent|peaceful|smile|smiling|spirit|tale\t
    🥰\t0\t0\t喜笑颜开\t三颗爱心的笑脸|心|我爱你|爱慕|相爱|笑脸|迷恋|陷入爱河\tsmiling face with hearts\t3|adore|crush|face|heart|hearts|ily|love|romance|smile|smiling|you\t
    😍\t0\t0\t花痴\t我爱你|爱|红心|脸\tsmiling face with heart-eyes\t143|bae|eye|face|feels|heart-eyes|hearts|ily|kisses|love|romance|romantic|smile|xoxo\t
    🤩\t0\t0\t好崇拜哦\t兴奋|咧嘴笑|满天星|满眼星|脸|追星族|露齿笑\tstar-struck\texcited|eyes|face|grinning|smile|star|starry-eyed|wow\t
    😘\t0\t0\t飞吻\t亲亲|想你|我爱你|眨眼|脸\tface blowing a kiss\tadorbs|bae|blowing|face|flirt|heart|ily|kiss|love|lover|miss|muah|romantic|smooch|xoxo|you\t
    😗\t0\t0\t亲亲\t亲吻|吻|脸\tkissing face\t143|date|dating|face|flirt|ily|kiss|love|smooch|smooches|xoxo|you\t
    ☺️\t0\t0\t微笑\t呵呵|开心|放松|笑|脸\tsmiling face\tface|happy|outlined|relaxed|smile|smiling\t
    😚\t0\t0\t羞涩亲亲\t亲亲|吻|我爱你|羞涩|脸|闭眼|闭眼亲吻\tkissing face with closed eyes\t143|bae|blush|closed|date|dating|eye|eyes|face|flirt|ily|kisses|kissing|smooches|xoxo\t
    😙\t0\t0\t微笑亲亲\t亲亲|吻|微笑|笑颜亲吻|脸\tkissing face with smiling eyes\t143|closed|date|dating|eye|eyes|face|flirt|ily|kiss|kisses|kissing|love|night|smile|smiling\t
    🥲\t0\t0\t含泪的笑脸\t喜悦|喜极而泣|幸福|微笑|微笑的|感动|感动的|感恩的|感激|眼泪|笑中带泪|笑脸|自豪|苦中作乐|释怀的|骄傲的\tsmiling face with tear\tface|glad|grateful|happy|joy|pain|proud|relieved|smile|smiley|smiling|tear|touched\t
    😋\t0\t0\t好吃\t口水|哈喇子|津津有味|流口水|美味|脸\tface savoring food\tdelicious|eat|face|food|full|hungry|savor|smile|smiling|tasty|um|yum|yummy\t
    😛\t0\t0\t吐舌\t吐舌头的脸|太好了|脸|舌头|调皮\tface with tongue\tawesome|cool|face|nice|party|stuck-out|sweet|tongue\t
    😜\t0\t0\t单眼吐舌\t单眼|古怪|吐舌|开玩笑|怪人|挤眉弄眼|脸\twinking face with tongue\tcrazy|epic|eye|face|funny|joke|loopy|nutty|party|stuck-out|tongue|wacky|weirdo|wink|winking|yolo\t
    🤪\t0\t0\t滑稽\t大小眼|大眼|小眼|滑稽的脸|疯狂的脸|疯眼|疯脸|脸\tzany face\tcrazy|eye|eyes|face|goofy|large|small|zany\t
    😝\t0\t0\t眯眼吐舌\t可怕|吐舌|尝|眯眼|眼睛|脸|都好|随便\tsquinting face with tongue\tclosed|eye|eyes|face|gross|horrible|omg|squinting|stuck-out|taste|tongue|whatever|yolo\t
    🤑\t0\t0\t发财\t拜金|脸|见钱眼开|金钱至上|钱\tmoney-mouth face\tface|money|money-mouth|mouth|paid\t
    🤗\t0\t0\t抱抱\t抱|拥抱|笑|脸\tsmiling face with open hands\tface|hands|hug|hugging|open|smiling\t
    🤭\t0\t0\t不说\t不可说|傻笑|吃吃傻笑|哎呀|意外|捂嘴而笑|猛然发现|秘密|脸\tface with hand over mouth\tface|giggle|giggling|hand|mouth|oops|realization|secret|shock|sudden|surprise|whoops\t
    🫢\t0\t0\t睁眼捂嘴\t哇塞|哑口无言|害怕|尴尬|怀疑|惊奇|惊愕|惊讶|敬畏|震惊\tface with open eyes and hand over mouth\tamazement|awe|disbelief|embarrass|eyes|face|gasp|hand|mouth|omg|open|over|quiet|scared|shock|surprise\t
    🫣\t0\t0\t偷看\t偷窥|凝视|害怕|害羞|尴尬|迷住\tface with peeking eye\tcaptivated|embarrass|eye|face|hide|hiding|peek|peeking|peep|scared|shy|stare\t
    🤫\t0\t0\t安静的脸\t嘘|嘘声手势的脸|安静\tshushing face\tface|quiet|shh|shush|shushing\t
    🤔\t0\t0\t想一想\t思考|想|想事情|脸\tthinking face\tchin|consider|face|hmm|ponder|pondering|thinking|wondering\t
    🫡\t0\t0\t致敬\t军队|好|好的|收到|敬礼|是|阳光\tsaluting face\tface|good|luck|ma’am|ok|respect|salute|saluting|sir|troops|yes\t
    🤐\t0\t0\t闭嘴\t住嘴|嘴|封口|秘密|脸\tzipper-mouth face\tface|keep|mouth|quiet|secret|shut|zip|zipper|zipper-mouth\t
    🤨\t0\t0\t挑眉\t不信任|不敢置信|不赞同|怀疑|氧起眉毛的脸|眉毛上挑的脸|脸\tface with raised eyebrow\tdisapproval|disbelief|distrust|emoji|eyebrow|face|hmm|mild|raised|skeptic|skeptical|skepticism|surprise|what\t
    😐️\t0\t0\t冷漠\t无感|脸|表情空洞|面无表情\tneutral face\tawkward|blank|deadpan|expressionless|face|fine|jealous|meh|neutral|oh|shade|straight|unamused|unhappy|unimpressed|whatever\t
    😑\t0\t0\t无语\t没有反应|绷着脸|脸|茫然|面无表情\texpressionless face\tawkward|dead|expressionless|face|fine|inexpressive|jealous|meh|not|oh|omg|straight|uh|unhappy|unimpressed|whatever\t
    😶\t0\t0\t沉默\t嘴|安静|没嘴|秘密|脸\tface without mouth\tawkward|blank|expressionless|face|mouth|mouthless|mute|quiet|secret|silence|silent|speechless\t
    🫥\t0\t0\t虚线脸\t内向|无所谓|沮丧|消失|隐形|隐藏\tdotted line face\tdepressed|disappear|dotted|face|hidden|hide|introvert|invisible|line|meh|whatever|wtv\t
    😶‍🌫️\t0\t0\t迷茫\t迷茫\tface in clouds\tabsentminded|clouds|face|fog|head\t
    😏\t0\t0\t得意\t假笑|冷笑|得意的笑|脸|诡异地笑\tsmirking face\tboss|dapper|face|flirt|homie|kidding|leer|shade|slick|sly|smirk|smug|snicker|suave|suspicious|swag\t
    😒\t0\t0\t不高兴\t不屑|不服|不爽的脸|脸|郁闷|鄙视|随便啦\tunamused face\t...|bored|face|fine|jealous|jel|jelly|pissed|smh|ugh|uhh|unamused|unhappy|weird|whatever\t
    🙄\t0\t0\t翻白眼\t不敢苟同|无语|白眼|脸|随便啦\tface with rolling eyes\teyeroll|eyes|face|rolling|shade|ugh|whatever\t
    😬\t0\t0\t龇牙咧嘴\t咬牙切齿|尴尬|牙医|脸|露齿|露齿而笑|鬼脸\tgrimacing face\tawk|awkward|dentist|face|grimace|grimacing|grinning|smile|smiling\t
    😮‍💨\t0\t0\t呼气\t叹息|叹气|吹气|呼气的脸|唉|无奈|松一口气|疲惫|笑脸|释然\tface exhaling\tblow|blowing|exhale|exhaling|exhausted|face|gasp|groan|relief|sigh|smiley|smoke|whisper|whistle\t
    🤥\t0\t0\t说谎\t匹诺曹|脸|长鼻子|长鼻子脸\tlying face\tface|liar|lie|lying|pinocchio\t
    🫨\t0\t0\t颤抖\t哇|地震|天啊|惊喜|惊慌|晕头转向|疯狂|脸|震动|震惊\tshaking face\tcrazy|daze|earthquake|face|omg|panic|shaking|shock|surprise|vibrate|whoa|wow\t
    🙂‍↔️\t0\t0\t左右摇头\t否定|摇头\thead shaking horizontally\thead|horizontally|no|shake|shaking\t
    🙂‍↕️\t0\t0\t上下点头\t点头，肯定\thead shaking vertically\thead|nod|shaking|vertically|yes\t
    😌\t0\t0\t松了口气\t如释重负|松口气|脸|蝉\trelieved face\tcalm|face|peace|relief|relieved|zen\t
    😔\t0\t0\t沉思\t失落|心事重重|忧虑|脸\tpensive face\tawful|bored|dejected|died|disappointed|face|losing|lost|pensive|sad|sucks\t
    😪\t0\t0\t困\t哭|想睡|满脸睡容|疲惫|睡觉|瞌睡|脸\tsleepy face\tcrying|face|good|night|sad|sleep|sleeping|sleepy|tired\t
    🤤\t0\t0\t流口水\t口水|垂涎|垂涎三尺|流口水的脸|脸\tdrooling face\tdrooling|face\t
    😴\t0\t0\t睡着了\t呼噜|小睡|想睡|打呼|晚安|睡容|睡觉|累|累了|脸\tsleeping face\tbed|bedtime|face|good|goodnight|nap|night|sleep|sleeping|tired|whatever|yawn|zzz\t
    🫩\t0\t1\t有眼袋\t厌倦|困倦|晚睡|熬夜|疲倦|疲劳|疲惫|眼|眼袋|脸\tface with bags under eyes\tbags|bored|exhausted|eyes|face|fatigued|late|sleepy|tired|weary\t
    😷\t0\t0\t感冒\t医生|口罩|戴口罩|戴口罩的脸|生病|病菌|脸\tface with medical mask\tcold|dentist|dermatologist|doctor|dr|face|germs|mask|medical|medicine|sick\t
    🤒\t0\t0\t发烧\t体温计|咬着体温计的脸|温度计|生病|脸|量体温\tface with thermometer\tface|ill|sick|thermometer\t
    🤕\t0\t0\t受伤\t头绑绷带|打绷带|脸\tface with head-bandage\tbandage|face|head-bandage|hurt|injury|ouch\t
    🤢\t0\t0\t恶心\t吐|呕|恶心作呕的脸|脸|脸绿了\tnauseated face\tface|gross|nasty|nauseated|sick|vomit\t
    🤮\t0\t0\t呕吐\t不舒服|吐|呕吐的脸|生病|病容|病恹恹|脸\tface vomiting\tbarf|ew|face|gross|puke|sick|spew|throw|up|vomit|vomiting\t
    🤧\t0\t0\t打喷嚏\t喷嚏|打喷嚏的脸|生病|脸|鼻涕\tsneezing face\tface|fever|flu|gesundheit|sick|sneeze|sneezing\t
    🥵\t0\t0\t脸发烧\t中暑|冒汗|出汗|发烧|发热|吐舌|心狂跳|热|脸红\thot face\tdying|face|feverish|heat|hot|panting|red-faced|stroke|sweating|tongue\t
    🥶\t0\t0\t冷脸\t冰柱|冷|冷冰冰|冻|冻僵|满面寒霜|脸|脸色发青|蓝色|零下\tcold face\tblue|blue-faced|cold|face|freezing|frostbite|icicles|subzero|teeth\t
    🥴\t0\t0\t头昏眼花\t两眼不平|喝醉|嘴唇颤抖|头晕目眩|头晕眼花|微醉|微醺|波浪嘴形|眩晕的脸|眼花|醉醺醺\twoozy face\tdizzy|drunk|eyes|face|intoxicated|mouth|tipsy|uneven|wavy|woozy\t
    😵\t0\t0\t晕头转向\t头晕|头晕眼花|晕头|晕头的脸|脸\tface with crossed-out eyes\tcrossed-out|dead|dizzy|eyes|face|feels|knocked|out|sick|tired\t
    😵‍💫\t0\t0\t晕\t哇|哎呀|头晕|笑脸|迷糊\tface with spiral eyes\tconfused|dizzy|eyes|face|hypnotized|omg|smiley|spiral|trouble|whoa|woah|woozy\t
    🤯\t0\t0\t爆炸头\t不可能|印象深刻|吓到了|惊吓|震惊\texploding head\tblown|explode|exploding|head|mind|mindblown|no|shocked|way\t
    🤠\t0\t0\t牛仔帽脸\t帽|牛仔|脸\tcowboy hat face\tcowboy|cowgirl|face|hat\t
    🥳\t0\t0\t聚会笑脸\t号角|喝彩|帽子|庆祝|派对|狂欢的脸|生日|聚会|脸|节日快乐\tpartying face\tbday|birthday|celebrate|celebration|excited|face|happy|hat|hooray|horn|party|partying\t
    🥸\t0\t0\t伪装的脸\t人物|伪装|眉毛|眼镜|胡子|脸|间谍|隐瞒身份|鼻子\tdisguised face\tdisguise|eyebrow|face|glasses|incognito|moustache|mustache|nose|person|spy|tache|tash\t
    😎\t0\t0\t墨镜笑脸\t墨镜|太阳镜|眼镜|耶|脸|酷\tsmiling face with sunglasses\tawesome|beach|bright|bro|chilling|cool|face|rad|relaxed|shades|slay|smile|style|sunglasses|swag|win\t
    🤓\t0\t0\t书呆子脸\t专家|书呆子|天才|奇葩|宅男|极客|眼镜|眼镜笑脸|聪明|脸\tnerd face\tbrainy|clever|expert|face|geek|gifted|glasses|intelligent|nerd|smart\t
    🧐\t0\t0\t带单片眼镜的脸\t单眼镜|古板|奢华|富有|戴单眼镜的脸\tface with monocle\tclassy|face|fancy|monocle|rich|stuffy|wealthy\t
    😕\t0\t0\t困扰\t不懂|不确定|困惑|疑惑|脸\tconfused face\tbefuddled|confused|confusing|dunno|face|frown|hm|meh|not|sad|sorry|sure\t
    🫤\t0\t0\t郁闷\t不相信|不确定|困惑|失望|怀疑|无所谓|无聊|沮丧|疑惑|迷惘\tface with diagonal mouth\tconfused|confusion|diagonal|disappointed|doubt|doubtful|face|frustrated|frustration|meh|mouth|skeptical|unsure|whatever|wtv\t
    😟\t0\t0\t担心\t不高兴|伤心|忧心的脸|意外|担忧|焦虑|紧张|脸\tworried face\tanxious|butterflies|face|nerves|nervous|sad|stress|stressed|surprised|worried|worry\t
    🙁\t0\t0\t微微不满\t不开心|不高兴|不高兴的脸|委屈|小委屈|心情不好|脸\tslightly frowning face\tface|frown|frowning|sad|slightly\t
    ☹️\t0\t0\t不满\t不爽|不高兴|委屈|皱眉|皱眉的脸|脸\tfrowning face\tface|frown|frowning|sad\t
    😮\t0\t0\t吃惊\t同情|啊|忘记|我不信|我的天|脸\tface with open mouth\tbelieve|face|forgot|mouth|omg|open|shocked|surprised|sympathy|unbelievable|unreal|whoa|wow|you\t
    😯\t0\t0\t缄默\t吃惊|哦|我的天|脸|静而无语\thushed face\tepic|face|hushed|omg|stunned|surprised|whoa|woah\t
    😲\t0\t0\t震惊\t不可以|惊|惊讶|惊讶的脸|没可能|绝不|脸\tastonished face\tastonished|cost|face|no|omg|shocked|totally|way\t
    😳\t0\t0\t脸红\t困惑|天呀|害羞|羞涩|脸|茫然|迷茫|难以置信\tflushed face\tamazed|awkward|crazy|dazed|dead|disbelief|embarrassed|face|flushed|geez|heat|hot|impressed|jeez|what|wow\t
    🥺\t0\t0\t恳求的脸\t可怜兮兮的眼神|大眼睛|小狗的脸|怜悯|祈求|祈求的脸|脸|请求\tpleading face\tbegging|big|eyes|face|mercy|not|pleading|please|pretty|puppy|sad|why\t
    🥹\t0\t0\t忍住泪水\t哭泣|喜极而泣|尴尬|悲伤|情绪|感激|感谢|抗拒|拜托|生气|自豪\tface holding back tears\tadmiration|aww|back|cry|embarrassed|face|feelings|grateful|gratitude|holding|joy|please|proud|resist|sad|tears\t
    😦\t0\t0\t啊\t惊讶|意外|目瞪口呆|脸\tfrowning face with open mouth\tcaught|face|frown|frowning|guard|mouth|open|scared|scary|surprise|what|wow\t
    😧\t0\t0\t极度痛苦\t痛|痛啊|痛苦|脸|难受\tanguished face\tanguished|face|forgot|scared|scary|stressed|surprise|unhappy|what|wow\t
    😨\t0\t0\t害怕\t不安|怕|恐怖|恐惧|脸\tfearful face\tafraid|anxious|blame|face|fear|fearful|scared|worried\t
    😰\t0\t0\t冷汗\t张嘴冒冷汗的脸|惊讶|无语|汗|焦虑|紧张|脸\tanxious face with sweat\tanxious|blue|cold|eek|face|mouth|nervous|open|rushed|scared|sweat|yikes\t
    😥\t0\t0\t失望但如释重负\t下次吧|出冷汗|失望|失望但解脱|如释重负|脸\tsad but relieved face\tanxious|call|close|complicated|disappointed|face|not|relieved|sad|sweat|time|whew\t
    😢\t0\t0\t哭\t伤心|哀伤|哭脸|泪|脸\tcrying face\tawful|cry|crying|face|feels|miss|sad|tear|triste|unhappy\t
    😭\t0\t0\t放声大哭\t哭|大哭|放声大哭的脸|泪|痛哭|脸\tloudly crying face\tbawling|cry|crying|face|loudly|sad|sob|tear|tears|unhappy\t
    😱\t0\t0\t吓死了\t吓死|害怕|尖叫|恐怖|惊吓大叫的脸|脸\tface screaming in fear\tepic|face|fear|fearful|munch|scared|scream|screamer|screaming|shocked|surprised|woah\t
    😖\t0\t0\t困惑\t困惑的脸|焦头烂额|纠结|脸\tconfounded face\tannoyed|confounded|confused|cringe|distraught|face|feels|frustrated|mad|sad\t
    😣\t0\t0\t痛苦\t专注|入定|头痛|忍耐|脸|难受\tpersevering face\tconcentrate|concentration|face|focus|headache|persevere|persevering\t
    😞\t0\t0\t失望\t不高兴|失望的脸|脸|难过\tdisappointed face\tawful|blame|dejected|disappointed|face|fail|losing|sad|unhappy\t
    😓\t0\t0\t汗\t冒冷汗|冒汗|冷|尴尬|担心|脸\tdowncast face with sweat\tclose|cold|downcast|face|feels|headache|nervous|sad|scared|sweat|yikes\t
    😩\t0\t0\t累死了\t疲倦|疲劳|疲惫|累|脸\tweary face\tcrying|face|fail|feels|hungry|mad|nooo|sad|sleepy|tired|unhappy|weary\t
    😫\t0\t0\t累\t倦容|疲倦|疲劳|疲惫|脸\ttired face\tcost|face|feels|nap|sad|sneeze|tired\t
    🥱\t0\t0\t打呵欠\t呵欠|哈欠|困|困倦|夜里|打哈欠|打哈欠的脸|无聊|昏昏欲睡|晚安|疲倦|累\tyawning face\tbedtime|bored|face|goodnight|nap|night|sleep|sleepy|tired|whatever|yawn|yawning|zzz\t
    😤\t0\t0\t傲慢\t不爽|愤怒|气炸了|胜利|自负|赢|趾高气昂\tface with steam from nose\tanger|angry|face|feels|fume|fuming|furious|fury|mad|nose|steam|triumph|unhappy|won\t
    😡\t0\t0\t怒火中烧\t发火|发飙|怒|生气|脸\tenraged face\tanger|angry|enraged|face|feels|mad|maddening|pouting|rage|red|shade|unhappy|upset\t
    😠\t0\t0\t生气\t不爽|不高兴|怒|愤怒|脸\tangry face\tanger|angry|blame|face|feels|frustrated|mad|maddening|rage|shade|unhappy|upset\t
    🤬\t0\t0\t嘴上有符号的脸\t不爽|发誓|咒骂|生气|碎碎唸的脸|脸|诅咒\tface with symbols on mouth\tcensor|cursing|cussing|face|mad|mouth|pissed|swearing|symbols\t
    😈\t0\t0\t恶魔微笑\t幻想|微笑|犄角|神话故事|脸|邪魔\tsmiling face with horns\tdemon|devil|evil|face|fairy|fairytale|fantasy|horns|purple|shade|smile|smiling|tale\t
    👿\t0\t0\t生气的恶魔\t带角的怒容|幻想|恶魔|犄角|脸|顽童\tangry face with horns\tangry|demon|devil|evil|face|fairy|fairytale|fantasy|horns|imp|mischievous|purple|shade|tale\t
    💀\t0\t0\t头骨\t妖怪|怪兽|死亡|神话故事|脸|身体|骷髅\tskull\tbody|dead|death|face|fairy|fairytale|i’m|lmao|monster|tale|yolo\t
    ☠️\t0\t0\t骷髅\t交叉股骨|头骨|妖怪|怪物|死亡|海盗|脸|骨头\tskull and crossbones\tbone|crossbones|dead|death|face|monster|skull\t
    💩\t0\t0\t大便\t好臭|屎|怪物|粑粑|脸|臭\tpile of poo\tbs|comic|doo|dung|face|fml|monster|pile|poo|poop|smelly|smh|stink|stinks|stinky|turd\t
    🤡\t0\t0\t小丑脸\t小丑|脸\tclown face\tclown|face\t
    👹\t0\t0\t食人魔\t吓人|妖怪|幻想|日本|神话故事|脸|面具|鬼|魔鬼\togre\tcreature|devil|face|fairy|fairytale|fantasy|mask|monster|scary|tale\t
    👺\t0\t0\t小妖精\t妖怪|幻想|怪物|日本|神话故事|脸|鬼\tgoblin\tangry|creature|face|fairy|fairytale|fantasy|mask|mean|monster|tale\t
    👻\t0\t0\t鬼\t万圣节|妖怪|幻想|幽灵|怪物|神话故事|脸|鬼脸\tghost\tboo|creature|excited|face|fairy|fairytale|fantasy|halloween|haunting|monster|scary|silly|tale\t
    👽️\t0\t0\t外星人\tufo|外太空|外星|太空|幻想|星际|脸|飞碟\talien\tcreature|extraterrestrial|face|fairy|fairytale|fantasy|monster|space|tale|ufo\t
    👾\t0\t0\t外星怪物\tufo|外星|外星人|太空|怪物|星际|脸|飞碟\talien monster\talien|creature|extraterrestrial|face|fairy|fairytale|fantasy|game|gamer|games|monster|pixelated|space|tale|ufo\t
    🤖\t0\t0\t机器人\t怪物|脸\trobot\tface|monster\t
    😺\t0\t0\t大笑的猫\t哈哈|大笑的猫脸|猫脸|笑|脸\tgrinning cat\tanimal|cat|face|grinning|mouth|open|smile|smiling\t
    😸\t0\t0\t微笑的猫\t呵呵|微笑的猫脸|猫脸|笑|笑颜逐开|脸\tgrinning cat with smiling eyes\tanimal|cat|eye|eyes|face|grin|grinning|smile|smiling\t
    😹\t0\t0\t笑出眼泪的猫\t喜极而泣|快乐|猫脸|眼泪|笑出眼泪|笑出眼泪的猫脸|脸\tcat with tears of joy\tanimal|cat|face|joy|laugh|laughing|lol|tear|tears\t
    😻\t0\t0\t花痴的猫\twc|喜欢|心|猫|猫脸|脸|花痴|花痴的猫脸\tsmiling cat with heart-eyes\tanimal|cat|eye|face|heart|heart-eyes|love|smile|smiling\t
    😼\t0\t0\t奸笑的猫\t嘲讽笑容|奸笑|奸笑的猫脸|猫脸|脸|讽刺\tcat with wry smile\tanimal|cat|face|ironic|smile|wry\t
    😽\t0\t0\t亲亲猫\t亲亲|吻|猫脸|猫脸亲亲|脸|闭眼亲亲的猫脸\tkissing cat\tanimal|cat|closed|eye|eyes|face|kiss|kissing\t
    🙀\t0\t0\t疲倦的猫\t惊讶|猫脸|疲倦|疲倦的猫脸|疲劳|疲惫|累|脸\tweary cat\tanimal|cat|face|oh|surprised|weary\t
    😿\t0\t0\t哭泣的猫\t哭|哭泣的猫脸|泪|猫脸|眼泪|脸|难过\tcrying cat\tanimal|cat|cry|crying|face|sad|tear\t
    😾\t0\t0\t生气的猫\t猫脸|生气|生气的猫脸|脸\tpouting cat\tanimal|cat|face|pouting\t
    🙈\t0\t0\t非礼勿视\t不许看|别看|尴尬|糗|脸|蒙住眼睛|蒙眼\tsee-no-evil monkey\tembarrassed|evil|face|forbidden|forgot|gesture|hide|monkey|no|omg|prohibited|scared|secret|smh|watch\t
    🙉\t0\t0\t非礼勿听\t嘘|堵上耳朵|堵耳|猴子|脸\thear-no-evil monkey\tanimal|ears|evil|face|forbidden|gesture|hear|listen|monkey|no|not|prohibited|secret|shh|tmi\t
    🙊\t0\t0\t非礼勿言\t不许说|捂上嘴巴|捂嘴|秘密|脸\tspeak-no-evil monkey\tanimal|evil|face|forbidden|gesture|monkey|no|not|oops|prohibited|quiet|secret|speak|stealth\t
    💌\t0\t0\t情书\t信|心|邮件\tlove letter\theart|letter|love|mail|romance|valentine\t
    💘\t0\t0\t心中箭了\t一箭穿心|丘比特|我爱你|浪漫|爱情|箭|红心\theart with arrow\t143|adorbs|arrow|cupid|date|emotion|heart|ily|love|romance|valentine\t
    💝\t0\t0\t系有缎带的心\t我爱你|爱的礼物|绑丝带的心|送你一颗心\theart with ribbon\t143|anniversary|emotion|heart|ily|kisses|ribbon|valentine|xoxo\t
    💖\t0\t0\t闪亮的心\t我爱你|激动|红心|闪亮\tsparkling heart\t143|emotion|excited|good|heart|ily|kisses|morning|night|sparkle|sparkling|xoxo\t
    💗\t0\t0\t搏动的心\t亲亲|吻|我爱你|搏动|激动|紧张|红心\tgrowing heart\t143|emotion|excited|growing|heart|heartpulse|ily|kisses|muah|nervous|pulse|xoxo\t
    💓\t0\t0\t心跳\t心动|我爱你|爱\tbeating heart\t143|beating|cardio|emotion|heart|heartbeat|ily|love|pulsating|pulse\t
    💞\t0\t0\t舞动的心\t我爱你|旋转|涌动|跃动\trevolving hearts\t143|adorbs|anniversary|emotion|heart|hearts|revolving\t
    💕\t0\t0\t两颗心\t我爱你|爱情\ttwo hearts\t143|anniversary|date|dating|emotion|heart|hearts|ily|kisses|love|loving|two|xoxo\t
    💟\t0\t0\t心型装饰\t心|我爱你|装饰\theart decoration\t143|decoration|emotion|heart|hearth|purple|white\t
    ❣️\t0\t0\t心叹号\t叹号|心动|标点符号\theart exclamation\texclamation|heart|heavy|mark|punctuation\t
    💔\t0\t0\t心碎\t伤心\tbroken heart\tbreak|broken|crushed|emotion|heart|heartbroken|lonely|sad\t
    ❤️‍🔥\t0\t0\t火上之心\t渴望|燃烧|爱\theart on fire\tburn|fire|heart|love|lust|sacred\t
    ❤️‍🩹\t0\t0\t修复受伤的心灵\t修补|恢复|痊愈\tmending heart\thealthier|heart|improving|mending|recovering|recuperating|well\t
    ❤️\t0\t0\t红心\t心|爱\tred heart\temotion|heart|love|red\t
    🩷\t0\t0\t粉红色的心\t可爱|喜欢|心|感情|我爱你|爱|特殊|甜蜜|粉红|讨人喜欢\tpink heart\t143|adorable|cute|emotion|heart|ily|like|love|pink|special|sweet\t
    🧡\t0\t0\t橙心\t橘心|橘色|橘色的心|橙\torange heart\t143|heart|orange\t
    💛\t0\t0\t黄心\t我爱你|黄\tyellow heart\t143|cardiac|emotion|heart|ily|love|yellow\t
    💚\t0\t0\t绿心\t我爱你|绿\tgreen heart\t143|emotion|green|heart|ily|love|romantic\t
    💙\t0\t0\t蓝心\t我爱你|蓝\tblue heart\t143|blue|emotion|heart|ily|love|romance\t
    🩵\t0\t0\t浅蓝色的心\t可爱|喜欢|天蓝|心|感情|我爱你|浅蓝|爱|特殊|蓝绿|蓝绿色|青色\tlight blue heart\t143|blue|cute|cyan|emotion|heart|ily|light|like|love|sky|special|teal\t
    💜\t0\t0\t紫心\t我爱你|紫\tpurple heart\t143|bestest|emotion|heart|ily|love|purple\t
    🤎\t0\t0\t棕心\t心|心形|棕|棕色|棕色爱心|爱心\tbrown heart\t143|brown|heart\t
    🖤\t0\t0\t黑心\t心|邪恶|黑|黑色|黑色的心\tblack heart\tblack|evil|heart|wicked\t
    🩶\t0\t0\t灰心\t心|感情|我爱你|暗灰|灰|灰色|爱|特殊|银|银色\tgrey heart\t143|emotion|gray|grey|heart|ily|love|silver|slate|special\t
    🤍\t0\t0\t白心\t心|心形|爱心|白|白色|白色爱心\twhite heart\t143|heart|white\t
    💋\t0\t0\t唇印\t亲吻|吻|唇|性感|接吻|浪漫\tkiss mark\tdating|emotion|heart|kiss|kissing|lips|mark|romance|sexy\t
    💯\t0\t0\t一百分\t100|满分|百分百|绝对|考试\thundred points\t100|a+|agree|clearly|definitely|faithful|fleek|full|hundred|keep|perfect|point|score|true|truth|yup\t
    💢\t0\t0\t怒\t火大|生气|青筋\tanger symbol\tanger|angry|comic|mad|symbol|upset\t
    💥\t0\t0\t爆炸\t撞|旺|炸|爆\tcollision\tbomb|boom|collide|comic|explode\t
    💫\t0\t0\t头晕\t头晕目眩|星星|流星\tdizzy\tcomic|shining|shooting|star|stars\t
    💦\t0\t0\t汗滴\t喷溅|小水滴|小水珠|汗|泼贱|溅\tsweat droplets\tcomic|drip|droplet|droplets|drops|splashing|squirt|sweat|water|wet|work|workout\t
    💨\t0\t0\t尾气\t扬尘而去|放屁|烟|疾驰而去|飞奔而去\tdashing away\taway|cloud|comic|dash|dashing|fart|fast|go|gone|gotta|running|smoke\t
    🕳️\t0\t0\t洞\t井盖|坑|陷阱\thole\thole\t
    💬\t0\t0\t话语气泡\t发言|对话框|气泡|气泡对话框|气球|漫画\tspeech balloon\tballoon|bubble|comic|dialog|message|sms|speech|talk|text|typing\t
    👁️‍🗨️\t0\t0\t眼睛对话框\t对话框|目擊|眼睛\teye in speech bubble\tballoon|bubble|eye|speech|witness\t
    🗨️\t0\t0\t朝左的话语气泡\t对话框|话语\tleft speech bubble\tballoon|bubble|dialog|left|speech\t
    🗯️\t0\t0\t愤怒话语气泡\t右倾愤怒对话框|对话框|愤怒\tright anger bubble\tanger|angry|balloon|bubble|mad|right\t
    💭\t0\t0\t内心活动气泡\t对话框|思想|思想活动|想法|梦|气泡|泡泡对话框|白日梦\tthought balloon\tballoon|bubble|cartoon|cloud|comic|daydream|decisions|dream|idea|invent|invention|realize|think|thoughts|wonder\t
    💤\t0\t0\t睡着\t呼噜|困了|想睡|打呼|晚安|疲倦\tZZZ\tcomic|good|goodnight|night|sleep|sleeping|sleepy|tired|zzz\t
    👋\t1\t0\t挥手\t你好|再见|嗨|在吗|手|等一下|等等|该走了\twaving hand\tbye|cya|g2g|greetings|gtg|hand|hello|hey|hi|later|outtie|ttfn|ttyl|wave|yo|you\t👋🏻 👋🏼 👋🏽 👋🏾 👋🏿
    🤚\t1\t0\t立起的手背\t举起|举起手背|手|手背|立起\traised back of hand\tback|backhand|hand|raised\t🤚🏻 🤚🏼 🤚🏽 🤚🏾 🤚🏿
    🖐️\t1\t0\t手掌\t举起张开的手掌|击掌|布|手|禁止\thand with fingers splayed\tfinger|fingers|hand|raised|splayed|stop\t🖐🏻 🖐🏼 🖐🏽 🖐🏾 🖐🏿
    ✋️\t1\t0\t举起手\t举手|举起的手|五指|停|击掌|手\traised hand\t5|five|hand|high|raised|stop\t✋🏻 ✋🏼 ✋🏽 ✋🏾 ✋🏿
    🖖\t1\t0\t瓦肯举手礼\t手|敬礼|斯波克|星际迷航|瓦肯\tvulcan salute\tfinger|hand|hands|salute|vulcan\t🖖🏻 🖖🏼 🖖🏽 🖖🏾 🖖🏿
    🫱\t1\t0\t向右的手\t伸手|右|右手|向右|手|握手\trightwards hand\thand|handshake|hold|reach|right|rightward|rightwards|shake\t🫱🏻 🫱🏼 🫱🏽 🫱🏾 🫱🏿
    🫲\t1\t0\t向左的手\t伸手|向左|左|左手|手|握手\tleftwards hand\thand|handshake|hold|left|leftward|leftwards|reach|shake\t🫲🏻 🫲🏼 🫲🏽 🫲🏾 🫲🏿
    🫳\t1\t0\t掌心向下的手\t下投|手|扔掉|拿起|捡起|解散|驱赶\tpalm down hand\tdismiss|down|drop|dropped|hand|palm|pick|shoo|up\t🫳🏻 🫳🏼 🫳🏽 🫳🏾 🫳🏿
    🫴\t1\t0\t掌心向上的手\t不知道|召唤|告诉我|手|拿着|接住|提供|过来|送出\tpalm up hand\tbeckon|catch|come|hand|hold|know|lift|me|offer|palm|tell\t🫴🏻 🫴🏼 🫴🏽 🫴🏾 🫴🏿
    🫷\t1\t0\t向左推\t中止|停止|击掌|向左|往左|手|拒绝|推|暂停|等等|阻挡\tleftwards pushing hand\tblock|five|halt|hand|high|hold|leftward|leftwards|pause|push|pushing|refuse|slap|stop|wait\t🫷🏻 🫷🏼 🫷🏽 🫷🏾 🫷🏿
    🫸\t1\t0\t向右推\t中止|停止|击掌|向右|往右|手|拒绝|推|暂停|等等|阻挡\trightwards pushing hand\tblock|five|halt|hand|high|hold|pause|push|pushing|refuse|rightward|rightwards|slap|stop|wait\t🫸🏻 🫸🏼 🫸🏽 🫸🏾 🫸🏿
    👌\t1\t0\tOK\tok|ok 手势|可以|同意|好的|当然|手|没问题|确定\tOK hand\tawesome|bet|dope|fleek|fosho|got|gotcha|hand|legit|ok|okay|pinch|rad|sure|sweet|three\t👌🏻 👌🏼 👌🏽 👌🏾 👌🏿
    🤌\t1\t0\t捏手指\t为什么|你到底在说什么|匮乏|审讯|强调|您要什么|手势|手指|挖苦|放松点\tpinched fingers\tfingers|gesture|hand|hold|huh|interrogation|patience|pinched|relax|sarcastic|ugh|what|zip\t🤌🏻 🤌🏼 🤌🏽 🤌🏾 🤌🏿
    🤏\t1\t0\t捏合的手势\t一点|一点点|小|少|少量|手指|捏着|某种程度上\tpinching hand\tamount|bit|fingers|hand|little|pinching|small|sort\t🤏🏻 🤏🏼 🤏🏽 🤏🏾 🤏🏿
    ✌️\t1\t0\t胜利手势\tv|和平|成功|手|胜利\tvictory hand\thand|peace|v|victory\t✌🏻 ✌🏼 ✌🏽 ✌🏾 ✌🏿
    🤞\t1\t0\t交叉的手指\t交叉|幸运|手|手指|祝好运\tcrossed fingers\tcross|crossed|finger|fingers|hand|luck\t🤞🏻 🤞🏼 🤞🏽 🤞🏾 🤞🏿
    🫰\t1\t0\t食指与拇指交叉的手\t响指|心|手|昂贵|比心|爱|爱心|金钱|钞票\thand with index finger and thumb crossed\t<3|crossed|expensive|finger|hand|heart|index|love|money|snap|thumb\t🫰🏻 🫰🏼 🫰🏽 🫰🏾 🫰🏿
    🤟\t1\t0\t爱你的手势\t三种|我爱你|手|爱你\tlove-you gesture\tfingers|gesture|hand|ily|love|love-you|three|you\t🤟🏻 🤟🏼 🤟🏽 🤟🏾 🤟🏿
    🤘\t1\t0\t摇滚\t手|摇滚精神|燥起来|角|金属礼\tsign of the horns\tfinger|hand|horns|rock-on|sign\t🤘🏻 🤘🏼 🤘🏽 🤘🏾 🤘🏿
    🤙\t1\t0\t给我打电话\t手|打电话给我|电话|给我打电话的手势\tcall me hand\tcall|hand|hang|loose|me|shaka\t🤙🏻 🤙🏼 🤙🏽 🤙🏾 🤙🏿
    👈️\t1\t0\t反手食指向左指\t反手|向左指|手|指左|食指\tbackhand index pointing left\tbackhand|finger|hand|index|left|point|pointing\t👈🏻 👈🏼 👈🏽 👈🏾 👈🏿
    👉️\t1\t0\t反手食指向右指\t反手|向右指|手|指右|食指\tbackhand index pointing right\tbackhand|finger|hand|index|point|pointing|right\t👉🏻 👉🏼 👉🏽 👉🏾 👉🏿
    👆️\t1\t0\t反手食指向上指\t反手|向上指|手|指上|食指\tbackhand index pointing up\tbackhand|finger|hand|index|point|pointing|up\t👆🏻 👆🏼 👆🏽 👆🏾 👆🏿
    🖕\t1\t0\t竖中指\t中指|反手|手\tmiddle finger\tfinger|hand|middle\t🖕🏻 🖕🏼 🖕🏽 🖕🏾 🖕🏿
    👇️\t1\t0\t反手食指向下指\t反手|向下指|手|指下|食指\tbackhand index pointing down\tbackhand|down|finger|hand|index|point|pointing\t👇🏻 👇🏼 👇🏽 👇🏾 👇🏿
    ☝️\t1\t0\t食指向上指\t向上指|手|指上|食指\tindex pointing up\tfinger|hand|index|point|pointing|this|up\t☝🏻 ☝🏼 ☝🏽 ☝🏾 ☝🏿
    🫵\t1\t0\t指向观察者的食指\t伸出手指|你|戳|手指|指|指向\tindex pointing at the viewer\tat|finger|hand|index|pointing|poke|viewer|you\t🫵🏻 🫵🏼 🫵🏽 🫵🏾 🫵🏿
    👍️\t1\t0\t拇指向上\t同意|好|手|拇指|真棒|赞|赞成|顶一下\tthumbs up\t+1|good|hand|like|thumb|up|yes\t👍🏻 👍🏼 👍🏽 👍🏾 👍🏿
    👎️\t1\t0\t拇指向下\t不赞成|反对|否决|手|责备\tthumbs down\t-1|bad|dislike|down|good|hand|no|nope|thumb|thumbs\t👎🏻 👎🏼 👎🏽 👎🏾 👎🏿
    ✊️\t1\t0\t举起拳头\t举拳|团结|手|拳头|握拳\traised fist\tclenched|fist|hand|punch|raised|solidarity\t✊🏻 ✊🏼 ✊🏽 ✊🏾 ✊🏿
    👊\t1\t0\t出拳\t完全同意|手|打|拳|挥拳过来|绝对正确\toncoming fist\tabsolutely|agree|boom|bro|bruh|bump|clenched|correct|fist|hand|knuckle|oncoming|pound|punch|rock|ttyl\t👊🏻 👊🏼 👊🏽 👊🏾 👊🏿
    🤛\t1\t0\t朝左的拳头\t拳头|朝左\tleft-facing fist\tfist|left-facing|leftwards\t🤛🏻 🤛🏼 🤛🏽 🤛🏾 🤛🏿
    🤜\t1\t0\t朝右的拳头\t手|拳头|朝右\tright-facing fist\tfist|right-facing|rightwards\t🤜🏻 🤜🏼 🤜🏽 🤜🏾 🤜🏿
    👏\t1\t0\t鼓掌\t干得好|恭喜|拍手|赞成\tclapping hands\tapplause|approval|awesome|clap|congrats|congratulations|excited|good|great|hand|homie|job|nice|prayed|well|yay\t👏🏻 👏🏼 👏🏽 👏🏾 👏🏿
    🙌\t1\t0\t举双手\t举手|击掌|双手|庆祝|手\traising hands\tcelebration|gesture|hand|hands|hooray|praise|raised|raising\t🙌🏻 🙌🏼 🙌🏽 🙌🏾 🙌🏿
    🫶\t1\t0\t做成心形的双手\t手|比心|爱|爱你|爱心\theart hands\t<3|hands|heart|love|you\t🫶🏻 🫶🏼 🫶🏽 🫶🏾 🫶🏿
    👐\t1\t0\t张开双手\t十|双手|摊手\topen hands\thand|hands|hug|jazz|open|swerve\t👐🏻 👐🏼 👐🏽 👐🏾 👐🏿
    🤲\t1\t0\t掌心向上托起\t双掌|双掌向上|希望|祈祷|祷告\tpalms up together\tcupped|dua|hands|palms|pray|prayer|together|up|wish\t🤲🏻 🤲🏼 🤲🏽 🤲🏾 🤲🏿
    🤝\t1\t0\t握手\t一言为定|会面|协议|君子协定\thandshake\tagreement|deal|hand|meeting|shake\t🤝🏻 🤝🏼 🤝🏽 🤝🏾 🤝🏿
    🙏\t1\t0\t双手合十\t合掌|感恩|拜托|祈求|祈祷|祈福|祝福|谢谢\tfolded hands\tappreciate|ask|beg|blessed|bow|cmon|five|folded|gesture|hand|high|please|pray|thanks|thx\t🙏🏻 🙏🏼 🙏🏽 🙏🏾 🙏🏿
    ✍️\t1\t0\t写字\t写|手|笔\twriting hand\thand|write|writing\t✍🏻 ✍🏼 ✍🏽 ✍🏾 ✍🏿
    💅\t1\t0\t涂指甲油\t修指甲|忙完了|护手|指甲油|美甲|闷|随便啦\tnail polish\tbored|care|cosmetics|done|makeup|manicure|nail|polish|whatever\t💅🏻 💅🏼 💅🏽 💅🏾 💅🏿
    🤳\t1\t0\t自拍\t手机|相机\tselfie\tcamera|phone\t🤳🏻 🤳🏼 🤳🏽 🤳🏾 🤳🏿
    💪\t1\t0\t肌肉\t二头肌|健身房|强壮\tflexed biceps\tarm|beast|bench|biceps|bodybuilder|bro|curls|flex|gains|gym|jacked|muscle|press|ripped|strong|weightlift\t💪🏻 💪🏼 💪🏽 💪🏾 💪🏿
    🦾\t1\t0\t机械手臂\t义肢|手臂|无障碍\tmechanical arm\taccessibility|arm|mechanical|prosthetic\t
    🦿\t1\t0\t机械腿\t义肢|无障碍|腿\tmechanical leg\taccessibility|leg|mechanical|prosthetic\t
    🦵\t1\t0\t腿\t弯腿|肢体|脚|跛行|踢\tleg\tbent|foot|kick|knee|limb\t🦵🏻 🦵🏼 🦵🏽 🦵🏾 🦵🏿
    🦶\t1\t0\t脚\t足踝|踏|踝|踢|踩|踱\tfoot\tankle|feet|kick|stomp\t🦶🏻 🦶🏼 🦶🏽 🦶🏾 🦶🏿
    👂️\t1\t0\t耳朵\t仔细听|听|耳\tear\tbody|ears|hear|hearing|listen|listening|sound\t👂🏻 👂🏼 👂🏽 👂🏾 👂🏿
    🦻\t1\t0\t戴助听器的耳朵\t助听器|听力障碍|听障|失聪|无障碍|耳聋|聋\tear with hearing aid\taccessibility|aid|ear|hard|hearing\t🦻🏻 🦻🏼 🦻🏽 🦻🏾 🦻🏿
    👃\t1\t0\t鼻子\t嗅|气味|闻|鼻\tnose\tbody|noses|nosey|odor|smell|smells\t👃🏻 👃🏼 👃🏽 👃🏾 👃🏿
    🧠\t1\t0\t脑\t大脑|头脑|智慧|智能|聪明\tbrain\tintelligent|smart\t
    🫀\t1\t0\t心脏器官\t中心|器官|心率|心脏|心脏病学|心跳|真心|红心|解剖|身体\tanatomical heart\tanatomical|beat|cardiology|heart|heartbeat|organ|pulse|real|red\t
    🫁\t1\t0\t肺\t吸气|呼吸|呼吸作用|呼气|器官|肺部|身体\tlungs\tbreath|breathe|exhalation|inhalation|lung|organ|respiration\t
    🦷\t1\t0\t牙齿\t牙医|牙科医生|珍珠色|白色\ttooth\tdentist|pearly|teeth|white\t
    🦴\t1\t0\t骨头\t叉骨|狗|骨骼\tbone\tbones|dog|skeleton|wishbone\t
    👀\t1\t0\t双眼\t看|眼睛|窥视|身体\teyes\tbody|eye|face|googly|look|looking|omg|peep|see|seeing\t
    👁️\t1\t0\t眼睛\t单眼|看|眼|身体\teye\t1|body|one\t
    👅\t1\t0\t舌头\t啧啧地喝|舌|舔|身体\ttongue\tbody|lick|slurp\t
    👄\t1\t0\t嘴\t口|口红|吻|唇|唇膏\tmouth\tbeauty|body|kiss|kissing|lips|lipstick\t
    🫦\t1\t0\t咬住嘴唇\t不舒服|口红|咬嘴唇|嘴唇|害怕|性感|担心|接吻|焦虑|紧张|调情\tbiting lip\tanxious|bite|biting|fear|flirt|flirting|kiss|lip|lipstick|nervous|sexy|uncomfortable|worried|worry\t
    👶\t1\t0\t小宝贝\t孩子|宝宝|小毛头\tbaby\tbabies|children|goo|infant|newborn|pregnant|young\t👶🏻 👶🏼 👶🏽 👶🏾 👶🏿
    🧒\t1\t0\t儿童\t中性|小孩|年轻人|性别不明|性别中立\tchild\tbright-eyed|grandchild|kid|young|younger\t🧒🏻 🧒🏼 🧒🏽 🧒🏾 🧒🏿
    👦\t1\t0\t男孩\t儿童|孩子|小孩|男\tboy\tbright-eyed|child|grandson|kid|son|young|younger\t👦🏻 👦🏼 👦🏽 👦🏾 👦🏿
    👧\t1\t0\t女孩\t儿童|大眼女孩|女|女儿|孩子|小孩\tgirl\tbright-eyed|child|daughter|granddaughter|kid|virgo|young|younger|zodiac\t👧🏻 👧🏼 👧🏽 👧🏾 👧🏿
    🧑\t1\t0\t成人\t中性|性别中立|性格不明\tperson\tadult\t🧑🏻 🧑🏼 🧑🏽 🧑🏾 🧑🏿
    👱\t1\t0\t金色头发的人\t人|脸|金发\tperson: blond hair\tblond|blond-haired|human|person\t👱🏻 👱🏼 👱🏽 👱🏾 👱🏿
    👨\t1\t0\t男人\t兄弟|成人|男\tman\tadult|bro\t👨🏻 👨🏼 👨🏽 👨🏾 👨🏿
    🧔\t1\t0\t有胡子的人\t人|大胡子|男|络腮胡|胡子|胡须|腮帮子|连鬓胡子\tperson: beard\tbeard|bearded|person|whiskers\t🧔🏻 🧔🏼 🧔🏽 🧔🏾 🧔🏿
    🧔‍♂️\t1\t0\t有络腮胡子的男人\t男人|胡子\tman: beard\tbeard|bearded|man|whiskers\t🧔🏻‍♂️ 🧔🏼‍♂️ 🧔🏽‍♂️ 🧔🏾‍♂️ 🧔🏿‍♂️
    🧔‍♀️\t1\t0\t有络腮胡子的女人\t女人|胡子\twoman: beard\tbeard|bearded|whiskers|woman\t🧔🏻‍♀️ 🧔🏼‍♀️ 🧔🏽‍♀️ 🧔🏾‍♀️ 🧔🏿‍♀️
    👨‍🦰\t1\t0\t男人: 红发\t兄弟|成人|男|男人|红发\tman: red hair\tadult|bro|man|red hair\t👨🏻‍🦰 👨🏼‍🦰 👨🏽‍🦰 👨🏾‍🦰 👨🏿‍🦰
    👨‍🦱\t1\t0\t男人: 卷发\t兄弟|卷发|成人|男|男人\tman: curly hair\tadult|bro|curly hair|man\t👨🏻‍🦱 👨🏼‍🦱 👨🏽‍🦱 👨🏾‍🦱 👨🏿‍🦱
    👨‍🦳\t1\t0\t男人: 白发\t兄弟|成人|男|男人|白发\tman: white hair\tadult|bro|man|white hair\t👨🏻‍🦳 👨🏼‍🦳 👨🏽‍🦳 👨🏾‍🦳 👨🏿‍🦳
    👨‍🦲\t1\t0\t男人: 秃顶\t兄弟|成人|男|男人|秃顶\tman: bald\tadult|bald|bro|man\t👨🏻‍🦲 👨🏼‍🦲 👨🏽‍🦲 👨🏾‍🦲 👨🏿‍🦲
    👩\t1\t0\t女人\t女|淑女|金发\twoman\tadult|lady\t👩🏻 👩🏼 👩🏽 👩🏾 👩🏿
    👩‍🦰\t1\t0\t女人: 红发\t女|女人|淑女|红发|金发\twoman: red hair\tadult|lady|red hair|woman\t👩🏻‍🦰 👩🏼‍🦰 👩🏽‍🦰 👩🏾‍🦰 👩🏿‍🦰
    🧑‍🦰\t1\t0\t成人: 红发\t中性|性别中立|性格不明|成人|红发\tperson: red hair\tadult|person|red hair\t🧑🏻‍🦰 🧑🏼‍🦰 🧑🏽‍🦰 🧑🏾‍🦰 🧑🏿‍🦰
    👩‍🦱\t1\t0\t女人: 卷发\t卷发|女|女人|淑女|金发\twoman: curly hair\tadult|curly hair|lady|woman\t👩🏻‍🦱 👩🏼‍🦱 👩🏽‍🦱 👩🏾‍🦱 👩🏿‍🦱
    🧑‍🦱\t1\t0\t成人: 卷发\t中性|卷发|性别中立|性格不明|成人\tperson: curly hair\tadult|curly hair|person\t🧑🏻‍🦱 🧑🏼‍🦱 🧑🏽‍🦱 🧑🏾‍🦱 🧑🏿‍🦱
    👩‍🦳\t1\t0\t女人: 白发\t女|女人|淑女|白发|金发\twoman: white hair\tadult|lady|white hair|woman\t👩🏻‍🦳 👩🏼‍🦳 👩🏽‍🦳 👩🏾‍🦳 👩🏿‍🦳
    🧑‍🦳\t1\t0\t成人: 白发\t中性|性别中立|性格不明|成人|白发\tperson: white hair\tadult|person|white hair\t🧑🏻‍🦳 🧑🏼‍🦳 🧑🏽‍🦳 🧑🏾‍🦳 🧑🏿‍🦳
    👩‍🦲\t1\t0\t女人: 秃顶\t女|女人|淑女|秃顶|金发\twoman: bald\tadult|bald|lady|woman\t👩🏻‍🦲 👩🏼‍🦲 👩🏽‍🦲 👩🏾‍🦲 👩🏿‍🦲
    🧑‍🦲\t1\t0\t成人: 秃顶\t中性|性别中立|性格不明|成人|秃顶\tperson: bald\tadult|bald|person\t🧑🏻‍🦲 🧑🏼‍🦲 🧑🏽‍🦲 🧑🏾‍🦲 🧑🏿‍🦲
    👱‍♀️\t1\t0\t金发女\t女|金发\twoman: blond hair\tblond|blond-haired|blonde|hair|woman\t👱🏻‍♀️ 👱🏼‍♀️ 👱🏽‍♀️ 👱🏾‍♀️ 👱🏿‍♀️
    👱‍♂️\t1\t0\t金发男\t男|金发\tman: blond hair\tblond|blond-haired|hair|man\t👱🏻‍♂️ 👱🏼‍♂️ 👱🏽‍♂️ 👱🏾‍♂️ 👱🏿‍♂️
    🧓\t1\t0\t老年人\t中性|性别不明|性别中性|成人|熟龄|老人|老男人|老龄\tolder person\tadult|elderly|grandparent|old|person|wise\t🧓🏻 🧓🏼 🧓🏽 🧓🏾 🧓🏿
    👴\t1\t0\t老爷爷\t祖父|秃头|老人|老头\told man\tadult|bald|elderly|gramps|grandfather|grandpa|man|old|wise\t👴🏻 👴🏼 👴🏽 👴🏾 👴🏿
    👵\t1\t0\t老奶奶\t祖母|老人|老太\told woman\tadult|elderly|grandma|grandmother|granny|lady|old|wise|woman\t👵🏻 👵🏼 👵🏽 👵🏾 👵🏿
    🙍\t1\t0\t皱眉\t不开心|不满|不爽|失望|心烦意乱|恼火|沮丧|皱眉的人\tperson frowning\tannoyed|disappointed|disgruntled|disturbed|frown|frowning|frustrated|gesture|irritated|person|upset\t🙍🏻 🙍🏼 🙍🏽 🙍🏾 🙍🏿
    🙍‍♂️\t1\t0\t皱眉男\t不开心|男|皱眉|表情\tman frowning\tannoyed|disappointed|disgruntled|disturbed|frown|frowning|frustrated|gesture|irritated|man|upset\t🙍🏻‍♂️ 🙍🏼‍♂️ 🙍🏽‍♂️ 🙍🏾‍♂️ 🙍🏿‍♂️
    🙍‍♀️\t1\t0\t皱眉女\t不开心|女|皱眉\twoman frowning\tannoyed|disappointed|disgruntled|disturbed|frown|frowning|frustrated|gesture|irritated|upset|woman\t🙍🏻‍♀️ 🙍🏼‍♀️ 🙍🏽‍♀️ 🙍🏾‍♀️ 🙍🏿‍♀️
    🙎\t1\t0\t撅嘴\t不开心|不高兴|低落|噘嘴|失望|怒视|撅嘴的人|生闷气|皱眉|苦相|表情\tperson pouting\tdisappointed|downtrodden|frown|grimace|person|pouting|scowl|sulk|upset|whine\t🙎🏻 🙎🏼 🙎🏽 🙎🏾 🙎🏿
    🙎‍♂️\t1\t0\t撅嘴男\t不开心|噘嘴|男|表情\tman pouting\tdisappointed|downtrodden|frown|grimace|man|pouting|scowl|sulk|upset|whine\t🙎🏻‍♂️ 🙎🏼‍♂️ 🙎🏽‍♂️ 🙎🏾‍♂️ 🙎🏿‍♂️
    🙎‍♀️\t1\t0\t撅嘴女\t不开心|噘嘴|女\twoman pouting\tdisappointed|downtrodden|frown|grimace|pouting|scowl|sulk|upset|whine|woman\t🙎🏻‍♀️ 🙎🏼‍♀️ 🙎🏽‍♀️ 🙎🏾‍♀️ 🙎🏿‍♀️
    🙅\t1\t0\t禁止手势\t不允许|不可能|不行|不通过|反对|手|用手势表示不的人|禁止\tperson gesturing NO\tforbidden|gesture|hand|no|not|person|prohibit\t🙅🏻 🙅🏼 🙅🏽 🙅🏾 🙅🏿
    🙅‍♂️\t1\t0\t禁止手势男\t不行|反对|男|禁止\tman gesturing NO\tforbidden|gesture|hand|man|no|not|prohibit\t🙅🏻‍♂️ 🙅🏼‍♂️ 🙅🏽‍♂️ 🙅🏾‍♂️ 🙅🏿‍♂️
    🙅‍♀️\t1\t0\t禁止手势女\t不行|反对|女|禁止\twoman gesturing NO\tforbidden|gesture|hand|no|not|prohibit|woman\t🙅🏻‍♀️ 🙅🏼‍♀️ 🙅🏽‍♀️ 🙅🏾‍♀️ 🙅🏿‍♀️
    🙆\t1\t0\tOK手势\tok|ok手势|同意|女子用手势表示好|好的|手|手势|摆姿势|锻炼\tperson gesturing OK\texercise|gesture|gesturing|hand|ok|omg|person\t🙆🏻 🙆🏼 🙆🏽 🙆🏾 🙆🏿
    🙆‍♂️\t1\t0\tOK手势男\tok|ok手势男|可以|同意|好的|男|运动\tman gesturing OK\texercise|gesture|gesturing|hand|man|ok|omg\t🙆🏻‍♂️ 🙆🏼‍♂️ 🙆🏽‍♂️ 🙆🏾‍♂️ 🙆🏿‍♂️
    🙆‍♀️\t1\t0\tOK手势女\tok|ok手势女|可以|同意|女|好的\twoman gesturing OK\texercise|gesture|gesturing|hand|ok|omg|woman\t🙆🏻‍♀️ 🙆🏼‍♀️ 🙆🏽‍♀️ 🙆🏾‍♀️ 🙆🏿‍♀️
    💁\t1\t0\t前台\t介绍|伸手给小费|信息|八卦|帮助|手|拨弄头发|自信时髦|请您离开|随便啦\tperson tipping hand\tfetch|flick|flip|gossip|hand|person|sarcasm|sarcastic|sassy|seriously|tipping|whatever\t💁🏻 💁🏼 💁🏽 💁🏾 💁🏿
    💁‍♂️\t1\t0\t前台男\t前台|嘲讽|小费|男\tman tipping hand\tfetch|flick|flip|gossip|hand|man|sarcasm|sarcastic|sassy|seriously|tipping|whatever\t💁🏻‍♂️ 💁🏼‍♂️ 💁🏽‍♂️ 💁🏾‍♂️ 💁🏿‍♂️
    💁‍♀️\t1\t0\t前台女\t前台|女\twoman tipping hand\tfetch|flick|flip|gossip|hand|sarcasm|sarcastic|sassy|seriously|tipping|whatever|woman\t💁🏻‍♀️ 💁🏼‍♀️ 💁🏽‍♀️ 💁🏾‍♀️ 💁🏿‍♀️
    🙋\t1\t0\t举手\t举手的人|嗨|开心|我参加|我可以帮忙|我知道|手|看这里|选我\tperson raising hand\tgesture|hand|here|know|me|person|pick|question|raise|raising\t🙋🏻 🙋🏼 🙋🏽 🙋🏾 🙋🏿
    🙋‍♂️\t1\t0\t男生举手\t举手|发问|手势|男\tman raising hand\tgesture|hand|here|know|man|me|pick|question|raise|raising\t🙋🏻‍♂️ 🙋🏼‍♂️ 🙋🏽‍♂️ 🙋🏾‍♂️ 🙋🏿‍♂️
    🙋‍♀️\t1\t0\t女生举手\t举手|女\twoman raising hand\tgesture|hand|here|know|me|pick|question|raise|raising|woman\t🙋🏻‍♀️ 🙋🏼‍♀️ 🙋🏽‍♀️ 🙋🏾‍♀️ 🙋🏿‍♀️
    🧏\t1\t0\t失聪者\t听力|听力障碍|听障|无障碍|耳朵|耳聋|聋\tdeaf person\taccessibility|deaf|ear|gesture|hear|person\t🧏🏻 🧏🏼 🧏🏽 🧏🏾 🧏🏿
    🧏‍♂️\t1\t0\t失聪的男人\t听力障碍|男|耳朵|聋\tdeaf man\taccessibility|deaf|ear|gesture|hear|man\t🧏🏻‍♂️ 🧏🏼‍♂️ 🧏🏽‍♂️ 🧏🏾‍♂️ 🧏🏿‍♂️
    🧏‍♀️\t1\t0\t失聪的女人\t听力障碍|女|耳朵|聋\tdeaf woman\taccessibility|deaf|ear|gesture|hear|woman\t🧏🏻‍♀️ 🧏🏼‍♀️ 🧏🏽‍♀️ 🧏🏾‍♀️ 🧏🏿‍♀️
    🙇\t1\t0\t鞠躬\t不好意思|冥想|姿势|对不起|惭愧|感谢|懊悔|祈求宽恕|道歉|鞠躬的人\tperson bowing\tapology|ask|beg|bow|bowing|favor|forgive|gesture|meditate|meditation|person|pity|regret|sorry\t🙇🏻 🙇🏼 🙇🏽 🙇🏾 🙇🏿
    🙇‍♂️\t1\t0\t男生鞠躬\t不好意思|对不起|男|道歉\tman bowing\tapology|ask|beg|bow|bowing|favor|forgive|gesture|man|meditate|meditation|pity|regret|sorry\t🙇🏻‍♂️ 🙇🏼‍♂️ 🙇🏽‍♂️ 🙇🏾‍♂️ 🙇🏿‍♂️
    🙇‍♀️\t1\t0\t女生鞠躬\t不好意思|女|对不起|道歉|静思|鞠躬\twoman bowing\tapology|ask|beg|bow|bowing|favor|forgive|gesture|meditate|meditation|pity|regret|sorry|woman\t🙇🏻‍♀️ 🙇🏼‍♀️ 🙇🏽‍♀️ 🙇🏾‍♀️ 🙇🏿‍♀️
    🤦\t1\t0\t捂脸\t人|尴尬|恼怒|我的天哪|扶额|无语|难以置信|震惊\tperson facepalming\tagain|bewilder|disbelief|exasperation|facepalm|no|not|oh|omg|person|shock|smh\t🤦🏻 🤦🏼 🤦🏽 🤦🏾 🤦🏿
    🤦‍♂️\t1\t0\t男生捂脸\t尴尬|恼怒|我的天哪|扶额|捂脸|无奈|无语|男|男子捂脸|难以置信|震惊\tman facepalming\tagain|bewilder|disbelief|exasperation|facepalm|man|no|not|oh|omg|shock|smh\t🤦🏻‍♂️ 🤦🏼‍♂️ 🤦🏽‍♂️ 🤦🏾‍♂️ 🤦🏿‍♂️
    🤦‍♀️\t1\t0\t女生捂脸\t女|女子捂脸|尴尬|恼怒|我的天哪|扶额|捂脸|无奈|无语|难以置信|震惊\twoman facepalming\tagain|bewilder|disbelief|exasperation|facepalm|no|not|oh|omg|shock|smh|woman\t🤦🏻‍♀️ 🤦🏼‍♀️ 🤦🏽‍♀️ 🤦🏾‍♀️ 🤦🏿‍♀️
    🤷\t1\t0\t耸肩\t不关心|不知道|人|天晓得|怀疑|我哪知|我猜的|无所谓|无视\tperson shrugging\tdoubt|dunno|guess|idk|ignorance|indifference|knows|maybe|person|shrug|shrugging|whatever|who\t🤷🏻 🤷🏼 🤷🏽 🤷🏾 🤷🏿
    🤷‍♂️\t1\t0\t男生耸肩\t不关心|不知道|天晓得|怀疑|我哪知|我猜的|无所谓|无视|男|男子耸肩|耸肩\tman shrugging\tdoubt|dunno|guess|idk|ignorance|indifference|knows|man|maybe|shrug|shrugging|whatever|who\t🤷🏻‍♂️ 🤷🏼‍♂️ 🤷🏽‍♂️ 🤷🏾‍♂️ 🤷🏿‍♂️
    🤷‍♀️\t1\t0\t女生耸肩\t不关心|不知道|天晓得|女|女子耸肩|怀疑|我哪知|我猜的|无所谓|无视|耸肩\twoman shrugging\tdoubt|dunno|guess|idk|ignorance|indifference|knows|maybe|shrug|shrugging|whatever|who|woman\t🤷🏻‍♀️ 🤷🏼‍♀️ 🤷🏽‍♀️ 🤷🏾‍♀️ 🤷🏿‍♀️
    🧑‍⚕️\t1\t0\t卫生工作者\t医生|护士|治疗师\thealth worker\tdoctor|health|healthcare|nurse|therapist|worker\t🧑🏻‍⚕️ 🧑🏼‍⚕️ 🧑🏽‍⚕️ 🧑🏾‍⚕️ 🧑🏿‍⚕️
    👨‍⚕️\t1\t0\t男医生\t医护人员|医生|护士|治疗师|男|男人|男治疗师\tman health worker\tdoctor|health|healthcare|man|nurse|therapist|worker\t👨🏻‍⚕️ 👨🏼‍⚕️ 👨🏽‍⚕️ 👨🏾‍⚕️ 👨🏿‍⚕️
    👩‍⚕️\t1\t0\t女医生\t医护人员|医生|女|女人|女治疗师|护士|治疗师\twoman health worker\tdoctor|health|healthcare|nurse|therapist|woman|worker\t👩🏻‍⚕️ 👩🏼‍⚕️ 👩🏽‍⚕️ 👩🏾‍⚕️ 👩🏿‍⚕️
    🧑‍🎓\t1\t0\t学生\t毕业|毕业生\tstudent\tgraduate\t🧑🏻‍🎓 🧑🏼‍🎓 🧑🏽‍🎓 🧑🏾‍🎓 🧑🏿‍🎓
    👨‍🎓\t1\t0\t男学生\t学生|毕业|男\tman student\tgraduate|man|student\t👨🏻‍🎓 👨🏼‍🎓 👨🏽‍🎓 👨🏾‍🎓 👨🏿‍🎓
    👩‍🎓\t1\t0\t女学生\t女|学生|毕业\twoman student\tgraduate|student|woman\t👩🏻‍🎓 👩🏼‍🎓 👩🏽‍🎓 👩🏾‍🎓 👩🏿‍🎓
    🧑‍🏫\t1\t0\t老师\t教师|教授\tteacher\tinstructor|lecturer|professor\t🧑🏻‍🏫 🧑🏼‍🏫 🧑🏽‍🏫 🧑🏾‍🏫 🧑🏿‍🏫
    👨‍🏫\t1\t0\t男老师\t教师|教授|男|老师\tman teacher\tinstructor|lecturer|man|professor|teacher\t👨🏻‍🏫 👨🏼‍🏫 👨🏽‍🏫 👨🏾‍🏫 👨🏿‍🏫
    👩‍🏫\t1\t0\t女老师\t女|教师|教授|老师\twoman teacher\tinstructor|lecturer|professor|teacher|woman\t👩🏻‍🏫 👩🏼‍🏫 👩🏽‍🏫 👩🏾‍🏫 👩🏿‍🏫
    🧑‍⚖️\t1\t0\t法官\t法律\tjudge\tjustice|law|scales\t🧑🏻‍⚖️ 🧑🏼‍⚖️ 🧑🏽‍⚖️ 🧑🏾‍⚖️ 🧑🏿‍⚖️
    👨‍⚖️\t1\t0\t男法官\t正义|法官|法律|男\tman judge\tjudge|justice|law|man|scales\t👨🏻‍⚖️ 👨🏼‍⚖️ 👨🏽‍⚖️ 👨🏾‍⚖️ 👨🏿‍⚖️
    👩‍⚖️\t1\t0\t女法官\t女|正义|法官|法律\twoman judge\tjudge|justice|law|scales|woman\t👩🏻‍⚖️ 👩🏼‍⚖️ 👩🏽‍⚖️ 👩🏾‍⚖️ 👩🏿‍⚖️
    🧑‍🌾\t1\t0\t农民\t园丁\tfarmer\tgardener|rancher\t🧑🏻‍🌾 🧑🏼‍🌾 🧑🏽‍🌾 🧑🏾‍🌾 🧑🏿‍🌾
    👨‍🌾\t1\t0\t农夫\t农民|园丁|牧场主人|牧场工人|男\tman farmer\tfarmer|gardener|man|rancher\t👨🏻‍🌾 👨🏼‍🌾 👨🏽‍🌾 👨🏾‍🌾 👨🏿‍🌾
    👩‍🌾\t1\t0\t农妇\t农民|园丁|女|牧场主人|牧场工\twoman farmer\tfarmer|gardener|rancher|woman\t👩🏻‍🌾 👩🏼‍🌾 👩🏽‍🌾 👩🏾‍🌾 👩🏿‍🌾
    🧑‍🍳\t1\t0\t厨师\t做饭|大厨\tcook\tchef\t🧑🏻‍🍳 🧑🏼‍🍳 🧑🏽‍🍳 🧑🏾‍🍳 🧑🏿‍🍳
    👨‍🍳\t1\t0\t男厨师\t做饭|厨师|大厨|男\tman cook\tchef|cook|man\t👨🏻‍🍳 👨🏼‍🍳 👨🏽‍🍳 👨🏾‍🍳 👨🏿‍🍳
    👩‍🍳\t1\t0\t女厨师\t做饭|厨师|大厨|女\twoman cook\tchef|cook|woman\t👩🏻‍🍳 👩🏼‍🍳 👩🏽‍🍳 👩🏾‍🍳 👩🏿‍🍳
    🧑‍🔧\t1\t0\t技工\t水管工|电工\tmechanic\telectrician|plumber|tradesperson\t🧑🏻‍🔧 🧑🏼‍🔧 🧑🏽‍🔧 🧑🏾‍🔧 🧑🏿‍🔧
    👨‍🔧\t1\t0\t男技工\t技工|机械工|杂工|水管工|水管工人|电工|男\tman mechanic\telectrician|man|mechanic|plumber|tradesperson\t👨🏻‍🔧 👨🏼‍🔧 👨🏽‍🔧 👨🏾‍🔧 👨🏿‍🔧
    👩‍🔧\t1\t0\t女技工\t修理工|女|技工|水电工|水管工|水管工人|电工\twoman mechanic\telectrician|mechanic|plumber|tradesperson|woman\t👩🏻‍🔧 👩🏼‍🔧 👩🏽‍🔧 👩🏾‍🔧 👩🏿‍🔧
    🧑‍🏭\t1\t0\t工人\t工业|工厂|装配\tfactory worker\tassembly|factory|industrial|worker\t🧑🏻‍🏭 🧑🏼‍🏭 🧑🏽‍🏭 🧑🏾‍🏭 🧑🏿‍🏭
    👨‍🏭\t1\t0\t男工人\t工业|工人|工厂|男|组装工|装配\tman factory worker\tassembly|factory|industrial|man|worker\t👨🏻‍🏭 👨🏼‍🏭 👨🏽‍🏭 👨🏾‍🏭 👨🏿‍🏭
    👩‍🏭\t1\t0\t女工人\t女|工业|工人|工厂|装配\twoman factory worker\tassembly|factory|industrial|woman|worker\t👩🏻‍🏭 👩🏼‍🏭 👩🏽‍🏭 👩🏾‍🏭 👩🏿‍🏭
    🧑‍💼\t1\t0\t白领\t商人|建筑师|经理\toffice worker\tarchitect|business|manager|office|white-collar|worker\t🧑🏻‍💼 🧑🏼‍💼 🧑🏽‍💼 🧑🏾‍💼 🧑🏿‍💼
    👨‍💼\t1\t0\t男白领\t商人|建筑师|男|白领|经理\tman office worker\tarchitect|business|man|manager|office|white-collar|worker\t👨🏻‍💼 👨🏼‍💼 👨🏽‍💼 👨🏾‍💼 👨🏿‍💼
    👩‍💼\t1\t0\t女白领\t人物|商人|女|建筑师|白领|经理\twoman office worker\tarchitect|business|manager|office|white-collar|woman|worker\t👩🏻‍💼 👩🏼‍💼 👩🏽‍💼 👩🏾‍💼 👩🏿‍💼
    🧑‍🔬\t1\t0\t科学家\t化学家|工程学家|物理学家|生物学家\tscientist\tbiologist|chemist|engineer|mathematician|physicist\t🧑🏻‍🔬 🧑🏼‍🔬 🧑🏽‍🔬 🧑🏾‍🔬 🧑🏿‍🔬
    👨‍🔬\t1\t0\t男科学家\t化学家|工程学家|工程师|数学家|物理学家|生物学家|男|科学家\tman scientist\tbiologist|chemist|engineer|man|mathematician|physicist|scientist\t👨🏻‍🔬 👨🏼‍🔬 👨🏽‍🔬 👨🏾‍🔬 👨🏿‍🔬
    👩‍🔬\t1\t0\t女科学家\t化学家|女|工程学家|工程师|数学家|物理学家|生物学家|科学家\twoman scientist\tbiologist|chemist|engineer|mathematician|physicist|scientist|woman\t👩🏻‍🔬 👩🏼‍🔬 👩🏽‍🔬 👩🏾‍🔬 👩🏿‍🔬
    🧑‍💻\t1\t0\t程序员\t发明|开发人员|码农|软件\ttechnologist\tcoder|computer|developer|inventor|software\t🧑🏻‍💻 🧑🏼‍💻 🧑🏽‍💻 🧑🏾‍💻 🧑🏿‍💻
    👨‍💻\t1\t0\t男程序员\t发明家|工程师|开发人员|男|码农|程序员|软件\tman technologist\tcoder|computer|developer|inventor|man|software|technologist\t👨🏻‍💻 👨🏼‍💻 👨🏽‍💻 👨🏾‍💻 👨🏿‍💻
    👩‍💻\t1\t0\t女程序员\t发明家|女|工程师|开发人员|码农|程序员|软件\twoman technologist\tcoder|computer|developer|inventor|software|technologist|woman\t👩🏻‍💻 👩🏼‍💻 👩🏽‍💻 👩🏾‍💻 👩🏿‍💻
    🧑‍🎤\t1\t0\t歌手\t摇滚歌手|明星|演员|艺人\tsinger\tactor|entertainer|rock|rockstar|star\t🧑🏻‍🎤 🧑🏼‍🎤 🧑🏽‍🎤 🧑🏾‍🎤 🧑🏿‍🎤
    👨‍🎤\t1\t0\t男歌手\t摇滚歌手|明星|歌手|男|男演员|艺人\tman singer\tactor|entertainer|man|rock|rockstar|singer|star\t👨🏻‍🎤 👨🏼‍🎤 👨🏽‍🎤 👨🏾‍🎤 👨🏿‍🎤
    👩‍🎤\t1\t0\t女歌手\t女|摇滚歌手|明星|歌手|演员|艺人\twoman singer\tactor|entertainer|rock|rockstar|singer|star|woman\t👩🏻‍🎤 👩🏼‍🎤 👩🏽‍🎤 👩🏾‍🎤 👩🏿‍🎤
    🧑‍🎨\t1\t0\t艺术家\t画家\tartist\tpalette\t🧑🏻‍🎨 🧑🏼‍🎨 🧑🏽‍🎨 🧑🏾‍🎨 🧑🏿‍🎨
    👨‍🎨\t1\t0\t男艺术家\t男|画家|艺术\tman artist\tartist|man|palette\t👨🏻‍🎨 👨🏼‍🎨 👨🏽‍🎨 👨🏾‍🎨 👨🏿‍🎨
    👩‍🎨\t1\t0\t女艺术家\t女|画家|艺术\twoman artist\tartist|palette|woman\t👩🏻‍🎨 👩🏼‍🎨 👩🏽‍🎨 👩🏾‍🎨 👩🏿‍🎨
    🧑‍✈️\t1\t0\t飞行员\t飞机\tpilot\tplane\t🧑🏻‍✈️ 🧑🏼‍✈️ 🧑🏽‍✈️ 🧑🏾‍✈️ 🧑🏿‍✈️
    👨‍✈️\t1\t0\t男飞行员\t机长|男|飞机|飞行员\tman pilot\tman|pilot|plane\t👨🏻‍✈️ 👨🏼‍✈️ 👨🏽‍✈️ 👨🏾‍✈️ 👨🏿‍✈️
    👩‍✈️\t1\t0\t女飞行员\t女|机长|飞机|飞行员\twoman pilot\tpilot|plane|woman\t👩🏻‍✈️ 👩🏼‍✈️ 👩🏽‍✈️ 👩🏾‍✈️ 👩🏿‍✈️
    🧑‍🚀\t1\t0\t宇航员\t火箭\tastronaut\trocket|space\t🧑🏻‍🚀 🧑🏼‍🚀 🧑🏽‍🚀 🧑🏾‍🚀 🧑🏿‍🚀
    👨‍🚀\t1\t0\t男宇航员\t宇宙|宇航员|火箭|男|航天\tman astronaut\tastronaut|man|rocket|space\t👨🏻‍🚀 👨🏼‍🚀 👨🏽‍🚀 👨🏾‍🚀 👨🏿‍🚀
    👩‍🚀\t1\t0\t女宇航员\t女|宇宙|宇航员|火箭|航天\twoman astronaut\tastronaut|rocket|space|woman\t👩🏻‍🚀 👩🏼‍🚀 👩🏽‍🚀 👩🏾‍🚀 👩🏿‍🚀
    🧑‍🚒\t1\t0\t消防员\t消防车\tfirefighter\tfire|firetruck\t🧑🏻‍🚒 🧑🏼‍🚒 🧑🏽‍🚒 🧑🏾‍🚒 🧑🏿‍🚒
    👨‍🚒\t1\t0\t男消防员\t救火|消防|消防员|消防车|男\tman firefighter\tfire|firefighter|firetruck|man\t👨🏻‍🚒 👨🏼‍🚒 👨🏽‍🚒 👨🏾‍🚒 👨🏿‍🚒
    👩‍🚒\t1\t0\t女消防员\t女|救火|消防|消防员|消防车|火灾\twoman firefighter\tfire|firefighter|firetruck|woman\t👩🏻‍🚒 👩🏼‍🚒 👩🏽‍🚒 👩🏾‍🚒 👩🏿‍🚒
    👮\t1\t0\t警察\t交警|传唤|公安|卧底|武警|法警|警官|警方|逮捕\tpolice officer\tapprehend|arrest|citation|cop|law|officer|over|police|pulled|undercover\t👮🏻 👮🏼 👮🏽 👮🏾 👮🏿
    👮‍♂️\t1\t0\t男警察\t男|警官|警察\tman police officer\tapprehend|arrest|citation|cop|law|man|officer|over|police|pulled|undercover\t👮🏻‍♂️ 👮🏼‍♂️ 👮🏽‍♂️ 👮🏾‍♂️ 👮🏿‍♂️
    👮‍♀️\t1\t0\t女警察\t交警|公安|卧底|女|武警|法警|警官|警察|警方|逮捕\twoman police officer\tapprehend|arrest|citation|cop|law|officer|over|police|pulled|undercover|woman\t👮🏻‍♀️ 👮🏼‍♀️ 👮🏽‍♀️ 👮🏾‍♀️ 👮🏿‍♀️
    🕵️\t1\t0\t侦探\t特工|男|间谍\tdetective\tsleuth|spy\t🕵🏻 🕵🏼 🕵🏽 🕵🏾 🕵🏿
    🕵️‍♂️\t1\t0\t男侦探\t侦探|男|间谍\tman detective\tdetective|man|sleuth|spy\t🕵🏻‍♂️ 🕵🏼‍♂️ 🕵🏽‍♂️ 🕵🏾‍♂️ 🕵🏿‍♂️
    🕵️‍♀️\t1\t0\t女侦探\t侦探|女|特工|间谍\twoman detective\tdetective|sleuth|spy|woman\t🕵🏻‍♀️ 🕵🏼‍♀️ 🕵🏽‍♀️ 🕵🏾‍♀️ 🕵🏿‍♀️
    💂\t1\t0\t卫兵\t伦敦|卫士|守卫|白金汉宫\tguard\tbuckingham|helmet|london|palace\t💂🏻 💂🏼 💂🏽 💂🏾 💂🏿
    💂‍♂️\t1\t0\t男卫兵\t卫兵|卫士|守卫|男\tman guard\tbuckingham|guard|helmet|london|man|palace\t💂🏻‍♂️ 💂🏼‍♂️ 💂🏽‍♂️ 💂🏾‍♂️ 💂🏿‍♂️
    💂‍♀️\t1\t0\t女卫兵\t卫兵|卫士|女|守卫\twoman guard\tbuckingham|guard|helmet|london|palace|woman\t💂🏻‍♀️ 💂🏼‍♀️ 💂🏽‍♀️ 💂🏾‍♀️ 💂🏿‍♀️
    🥷\t1\t0\t忍者\t人物|侠客|刺客|士兵|战斗|打斗|狡猾|秘密|隐藏|隐身\tninja\tassassin|fight|fighter|hidden|person|secret|skills|sly|soldier|stealth|war\t🥷🏻 🥷🏼 🥷🏽 🥷🏾 🥷🏿
    👷\t1\t0\t建筑工人\t包工头|头盔|安全帽|工人|工程师|建筑|建造|搬砖|改造\tconstruction worker\tbuild|construction|fix|hardhat|hat|man|person|rebuild|remodel|repair|work|worker\t👷🏻 👷🏼 👷🏽 👷🏾 👷🏿
    👷‍♂️\t1\t0\t男建筑工人\t工人|建筑|男\tman construction worker\tbuild|construction|fix|hardhat|hat|man|rebuild|remodel|repair|work|worker\t👷🏻‍♂️ 👷🏼‍♂️ 👷🏽‍♂️ 👷🏾‍♂️ 👷🏿‍♂️
    👷‍♀️\t1\t0\t女建筑工人\t头盔|女|工人|建筑\twoman construction worker\tbuild|construction|fix|hardhat|hat|man|rebuild|remodel|repair|woman|work|worker\t👷🏻‍♀️ 👷🏼‍♀️ 👷🏽‍♀️ 👷🏾‍♀️ 👷🏿‍♀️
    🫅\t1\t0\t戴王冠的人\t君主|君威|国王|王冠|王后|王室|皇室|贵族\tperson with crown\tcrown|monarch|noble|person|regal|royal|royalty\t🫅🏻 🫅🏼 🫅🏽 🫅🏾 🫅🏿
    🤴\t1\t0\t王子\t皇家\tprince\tcrown|fairy|fairytale|fantasy|king|royal|royalty|tale\t🤴🏻 🤴🏼 🤴🏽 🤴🏾 🤴🏿
    👸\t1\t0\t公主\t皇冠|童话\tprincess\tcrown|fairy|fairytale|fantasy|queen|royal|royalty|tale\t👸🏻 👸🏼 👸🏽 👸🏾 👸🏿
    👳\t1\t0\t戴头巾的人\t头巾\tperson wearing turban\tperson|turban|wearing\t👳🏻 👳🏼 👳🏽 👳🏾 👳🏿
    👳‍♂️\t1\t0\t戴头巾的男人\t头巾|男\tman wearing turban\tman|turban|wearing\t👳🏻‍♂️ 👳🏼‍♂️ 👳🏽‍♂️ 👳🏾‍♂️ 👳🏿‍♂️
    👳‍♀️\t1\t0\t戴头巾的女人\t头巾|女|特本\twoman wearing turban\tturban|wearing|woman\t👳🏻‍♀️ 👳🏼‍♀️ 👳🏽‍♀️ 👳🏾‍♀️ 👳🏿‍♀️
    👲\t1\t0\t戴瓜皮帽的人\t人物|帽子|瓜皮帽\tperson with skullcap\tcap|chinese|gua|guapi|hat|mao|person|pi|skullcap\t👲🏻 👲🏼 👲🏽 👲🏾 👲🏿
    🧕\t1\t0\t带头饰的女人\t头巾|希贾布|戴头巾的女人\twoman with headscarf\tbandana|head|headscarf|hijab|kerchief|mantilla|tichel|woman\t🧕🏻 🧕🏼 🧕🏽 🧕🏾 🧕🏿
    🤵\t1\t0\t穿燕尾服的人\t人|新郎|正式|燕尾服|男人|穿燕尾服的男人\tperson in tuxedo\tformal|person|tuxedo|wedding\t🤵🏻 🤵🏼 🤵🏽 🤵🏾 🤵🏿
    🤵‍♂️\t1\t0\t穿礼服的男人\t男人|礼服\tman in tuxedo\tformal|groom|man|tuxedo|wedding\t🤵🏻‍♂️ 🤵🏼‍♂️ 🤵🏽‍♂️ 🤵🏾‍♂️ 🤵🏿‍♂️
    🤵‍♀️\t1\t0\t穿礼服的女人\t女人|礼服\twoman in tuxedo\tformal|tuxedo|wedding|woman\t🤵🏻‍♀️ 🤵🏼‍♀️ 🤵🏽‍♀️ 🤵🏾‍♀️ 🤵🏿‍♀️
    👰\t1\t0\t戴头纱的人\t人|头纱|婚礼|戴头纱的新娘|新娘|结婚\tperson with veil\tperson|veil|wedding\t👰🏻 👰🏼 👰🏽 👰🏾 👰🏿
    👰‍♂️\t1\t0\t戴头纱的男人\t头纱|男人\tman with veil\tman|veil|wedding\t👰🏻‍♂️ 👰🏼‍♂️ 👰🏽‍♂️ 👰🏾‍♂️ 👰🏿‍♂️
    👰‍♀️\t1\t0\t戴头纱的女人\t头纱|女人\twoman with veil\tbride|veil|wedding|woman\t👰🏻‍♀️ 👰🏼‍♀️ 👰🏽‍♀️ 👰🏾‍♀️ 👰🏿‍♀️
    🤰\t1\t0\t孕妇\t女人|怀孕|怀孕的女人\tpregnant woman\tpregnant|woman\t🤰🏻 🤰🏼 🤰🏽 🤰🏾 🤰🏿
    🫃\t1\t0\t怀孕的男人\t充满|吃撑|怀孕|男子|腹部|臃肿\tpregnant man\tbelly|bloated|full|man|overeat|pregnant\t🫃🏻 🫃🏼 🫃🏽 🫃🏾 🫃🏿
    🫄\t1\t0\t怀孕的人\t充满|吃撑|怀孕|腹部|臃肿\tpregnant person\tbelly|bloated|full|overeat|person|pregnant|stuffed\t🫄🏻 🫄🏼 🫄🏽 🫄🏾 🫄🏿
    🤱\t1\t0\t母乳喂养\t乳房|哺乳|喂奶|婴儿\tbreast-feeding\tbaby|breast|feeding|mom|mother|nursing|woman\t🤱🏻 🤱🏼 🤱🏽 🤱🏾 🤱🏿
    👩‍🍼\t1\t0\t哺乳的女人\t人物|保姆|哺乳|喂养|女人|妈咪|妈妈|婴儿|宝宝|母亲|爱\twoman feeding baby\tbaby|feed|feeding|mom|mother|nanny|newborn|nursing|woman\t👩🏻‍🍼 👩🏼‍🍼 👩🏽‍🍼 👩🏾‍🍼 👩🏿‍🍼
    👨‍🍼\t1\t0\t哺乳的男人\t人物|保姆|哺乳|哺育|喂养|婴儿|宝宝|新生儿|爱|父亲|父子情|父爱|男人\tman feeding baby\tbaby|dad|father|feed|feeding|man|nanny|newborn|nursing\t👨🏻‍🍼 👨🏼‍🍼 👨🏽‍🍼 👨🏾‍🍼 👨🏿‍🍼
    🧑‍🍼\t1\t0\t哺乳的人\t人|人物|保姆|哺乳|哺育|喂养|婴儿|宝宝|新生儿\tperson feeding baby\tbaby|feed|feeding|nanny|newborn|nursing|parent\t🧑🏻‍🍼 🧑🏼‍🍼 🧑🏽‍🍼 🧑🏾‍🍼 🧑🏿‍🍼
    👼\t1\t0\t小天使\t儿童|天使|孩子\tbaby angel\tangel|baby|church|face|fairy|fairytale|fantasy|tale\t👼🏻 👼🏼 👼🏽 👼🏾 👼🏿
    🎅\t1\t0\t圣诞老人\t圣诞|圣诞节|节日\tSanta Claus\tcelebration|christmas|claus|fairy|fantasy|father|holiday|merry|santa|tale|xmas\t🎅🏻 🎅🏼 🎅🏽 🎅🏾 🎅🏿
    🤶\t1\t0\t圣诞奶奶\t圣诞|圣诞节|节日\tMrs. Claus\tcelebration|christmas|claus|fairy|fantasy|holiday|merry|mother|mrs|santa|tale|xmas\t🤶🏻 🤶🏼 🤶🏽 🤶🏾 🤶🏿
    🧑‍🎄\t1\t0\t圣诞人\t人|人物|圣诞|圣诞帽|圣诞快乐|圣诞老人|圣诞老公公|节日\tMx Claus\tcelebration|christmas|claus|fairy|fantasy|holiday|merry|mx|santa|tale|xmas\t🧑🏻‍🎄 🧑🏼‍🎄 🧑🏽‍🎄 🧑🏾‍🎄 🧑🏿‍🎄
    🦸\t1\t0\t超级英雄\t女英雄|女超人|好人|英雄|蝙蝠侠|超人|超能力\tsuperhero\tgood|hero|superpower\t🦸🏻 🦸🏼 🦸🏽 🦸🏾 🦸🏿
    🦸‍♂️\t1\t0\t男超级英雄\t好人|男人|英雄|超能力\tman superhero\tgood|hero|man|superhero|superpower\t🦸🏻‍♂️ 🦸🏼‍♂️ 🦸🏽‍♂️ 🦸🏾‍♂️ 🦸🏿‍♂️
    🦸‍♀️\t1\t0\t女超级英雄\t女人|好人|英雄|超能力\twoman superhero\tgood|hero|heroine|superhero|superpower|woman\t🦸🏻‍♀️ 🦸🏼‍♀️ 🦸🏽‍♀️ 🦸🏾‍♀️ 🦸🏿‍♀️
    🦹\t1\t0\t超级大坏蛋\t人|坏蛋|大反派|恶魔|罪犯|超级恶棍|超能力|邪恶\tsupervillain\tbad|criminal|evil|superpower|villain\t🦹🏻 🦹🏼 🦹🏽 🦹🏾 🦹🏿
    🦹‍♂️\t1\t0\t男超级大坏蛋\t坏蛋|男人|罪犯|超能力\tman supervillain\tbad|criminal|evil|man|superpower|supervillain|villain\t🦹🏻‍♂️ 🦹🏼‍♂️ 🦹🏽‍♂️ 🦹🏾‍♂️ 🦹🏿‍♂️
    🦹‍♀️\t1\t0\t女超级大坏蛋\t坏蛋|女人|罪犯|超能力\twoman supervillain\tbad|criminal|evil|superpower|supervillain|villain|woman\t🦹🏻‍♀️ 🦹🏼‍♀️ 🦹🏽‍♀️ 🦹🏾‍♀️ 🦹🏿‍♀️
    🧙\t1\t0\t法师\t召唤|女巫|女魔术师|巫师|智者|法术|男巫|男魔术师|魔咒|魔术师\tmage\tfantasy|magic|play|sorcerer|sorceress|sorcery|spell|summon|witch|wizard\t🧙🏻 🧙🏼 🧙🏽 🧙🏾 🧙🏿
    🧙‍♂️\t1\t0\t男法师\t男巫|男魔术师\tman mage\tfantasy|mage|magic|man|play|sorcerer|sorceress|sorcery|spell|summon|witch|wizard\t🧙🏻‍♂️ 🧙🏼‍♂️ 🧙🏽‍♂️ 🧙🏾‍♂️ 🧙🏿‍♂️
    🧙‍♀️\t1\t0\t女法师\t女巫|女魔术师\twoman mage\tfantasy|mage|magic|play|sorcerer|sorceress|sorcery|spell|summon|witch|wizard|woman\t🧙🏻‍♀️ 🧙🏼‍♀️ 🧙🏽‍♀️ 🧙🏾‍♀️ 🧙🏿‍♀️
    🧚\t1\t0\t精灵\t仙女|仙子|童话|翅膀\tfairy\tfairytale|fantasy|myth|person|pixie|tale|wings\t🧚🏻 🧚🏼 🧚🏽 🧚🏾 🧚🏿
    🧚‍♂️\t1\t0\t仙人\t仙男|天卫十五|天卫四|男精灵\tman fairy\tfairy|fairytale|fantasy|man|myth|oberon|person|pixie|puck|tale|wings\t🧚🏻‍♂️ 🧚🏼‍♂️ 🧚🏽‍♂️ 🧚🏾‍♂️ 🧚🏿‍♂️
    🧚‍♀️\t1\t0\t仙女\t女精灵|妖精王后\twoman fairy\tfairy|fairytale|fantasy|myth|person|pixie|tale|titania|wings|woman\t🧚🏻‍♀️ 🧚🏼‍♀️ 🧚🏽‍♀️ 🧚🏾‍♀️ 🧚🏿‍♀️
    🧛\t1\t0\t吸血鬼\t万圣节|不死族|利牙|恐怖|毒牙|装扮服装|超自然\tvampire\tblood|dracula|fangs|halloween|scary|supernatural|teeth|undead\t🧛🏻 🧛🏼 🧛🏽 🧛🏾 🧛🏿
    🧛‍♂️\t1\t0\t男吸血鬼\t男不死族\tman vampire\tblood|fangs|halloween|man|scary|supernatural|teeth|undead|vampire\t🧛🏻‍♂️ 🧛🏼‍♂️ 🧛🏽‍♂️ 🧛🏾‍♂️ 🧛🏿‍♂️
    🧛‍♀️\t1\t0\t女吸血鬼\t女不死族\twoman vampire\tblood|fangs|halloween|scary|supernatural|teeth|undead|vampire|woman\t🧛🏻‍♀️ 🧛🏼‍♀️ 🧛🏽‍♀️ 🧛🏾‍♀️ 🧛🏿‍♀️
    🧜\t1\t0\t人鱼\t三叉戟|女人鱼|民间传说|海妖|海底|海洋生物|男人鱼|童话|美人鱼\tmerperson\tcreature|fairytale|folklore|ocean|sea|siren|trident\t🧜🏻 🧜🏼 🧜🏽 🧜🏾 🧜🏿
    🧜‍♂️\t1\t0\t男人鱼\t特里同\tmerman\tcreature|fairytale|folklore|neptune|ocean|poseidon|sea|siren|trident|triton\t🧜🏻‍♂️ 🧜🏼‍♂️ 🧜🏽‍♂️ 🧜🏾‍♂️ 🧜🏿‍♂️
    🧜‍♀️\t1\t0\t美人鱼\t女人鱼\tmermaid\tcreature|fairytale|folklore|merwoman|ocean|sea|siren|trident\t🧜🏻‍♀️ 🧜🏼‍♀️ 🧜🏽‍♀️ 🧜🏾‍♀️ 🧜🏿‍♀️
    🧝\t1\t0\t小精灵\t神秘|精灵|魔幻|魔法\telf\telves|enchantment|fantasy|folklore|magic|magical|myth\t🧝🏻 🧝🏼 🧝🏽 🧝🏾 🧝🏿
    🧝‍♂️\t1\t0\t男小精灵\t男性魔术\tman elf\telf|elves|enchantment|fantasy|folklore|magic|magical|man|myth\t🧝🏻‍♂️ 🧝🏼‍♂️ 🧝🏽‍♂️ 🧝🏾‍♂️ 🧝🏿‍♂️
    🧝‍♀️\t1\t0\t女小精灵\t女性魔术\twoman elf\telf|elves|enchantment|fantasy|folklore|magic|magical|myth|woman\t🧝🏻‍♀️ 🧝🏼‍♀️ 🧝🏽‍♀️ 🧝🏾‍♀️ 🧝🏿‍♀️
    🧞\t1\t0\t妖怪\t奇幻|愿望|擦拭神灯|杰尼|灯神|神灵|神秘|神话|精灵|镇尼\tgenie\tdjinn|fantasy|jinn|lamp|myth|rub|wishes\t
    🧞‍♂️\t1\t0\t男妖怪\t男神灵\tman genie\tdjinn|fantasy|genie|jinn|lamp|man|myth|rub|wishes\t
    🧞‍♀️\t1\t0\t女妖怪\t女神灵\twoman genie\tdjinn|fantasy|genie|jinn|lamp|myth|rub|wishes|woman\t
    🧟\t1\t0\t僵尸\t万圣节|不死族|半死不活|吓人|行尸走肉\tzombie\tapocalypse|dead|halloween|horror|scary|undead|walking\t
    🧟‍♂️\t1\t0\t男僵尸\t男行尸走肉\tman zombie\tapocalypse|dead|halloween|horror|man|scary|undead|walking|zombie\t
    🧟‍♀️\t1\t0\t女僵尸\t女行尸走肉\twoman zombie\tapocalypse|dead|halloween|horror|scary|undead|walking|woman|zombie\t
    🧌\t1\t0\t穴居巨怪\t幻想|怪兽|怪物|神话故事\ttroll\tfairy|fantasy|monster|tale|trolling\t
    💆\t1\t0\t按摩\t享受按摩的人|头痛|放松|水疗|治疗|紧张|缓解|美容|美容沙龙|面部\tperson getting massage\tface|getting|headache|massage|person|relax|relaxing|salon|soothe|spa|tension|therapy|treatment\t💆🏻 💆🏼 💆🏽 💆🏾 💆🏿
    💆‍♂️\t1\t0\t男生按摩\t头痛|按摩|男|脸\tman getting massage\tface|getting|headache|man|massage|relax|relaxing|salon|soothe|spa|tension|therapy|treatment\t💆🏻‍♂️ 💆🏼‍♂️ 💆🏽‍♂️ 💆🏾‍♂️ 💆🏿‍♂️
    💆‍♀️\t1\t0\t女生按摩\t女|按摩\twoman getting massage\tface|getting|headache|massage|relax|relaxing|salon|soothe|spa|tension|therapy|treatment|woman\t💆🏻‍♀️ 💆🏼‍♀️ 💆🏽‍♀️ 💆🏾‍♀️ 💆🏿‍♀️
    💇\t1\t0\t理发\t剪头|发型|理发师|理发的人|美发|美容|美容沙龙|美容院|造型师\tperson getting haircut\tbarber|beauty|chop|cosmetology|cut|groom|hair|haircut|parlor|person|shears|style\t💇🏻 💇🏼 💇🏽 💇🏾 💇🏿
    💇‍♂️\t1\t0\t男生理发\t剪头|理发|男\tman getting haircut\tbarber|beauty|chop|cosmetology|cut|groom|hair|haircut|man|parlor|person|shears|style\t💇🏻‍♂️ 💇🏼‍♂️ 💇🏽‍♂️ 💇🏾‍♂️ 💇🏿‍♂️
    💇‍♀️\t1\t0\t女生理发\t剪头|女|理发\twoman getting haircut\tbarber|beauty|chop|cosmetology|cut|groom|hair|haircut|parlor|person|shears|style|woman\t💇🏻‍♀️ 💇🏼‍♀️ 💇🏽‍♀️ 💇🏾‍♀️ 💇🏿‍♀️
    🚶\t1\t0\t行人\t压马路|徒步|散步|昂首阔步|竞走|行走的人|走路|远足|闲逛\tperson walking\tamble|gait|hike|man|pace|pedestrian|person|stride|stroll|walk|walking\t🚶🏻 🚶🏼 🚶🏽 🚶🏾 🚶🏿
    🚶‍♂️\t1\t0\t男行人\t徒步|男|走路\tman walking\tamble|gait|hike|man|pace|pedestrian|stride|stroll|walk|walking\t🚶🏻‍♂️ 🚶🏼‍♂️ 🚶🏽‍♂️ 🚶🏾‍♂️ 🚶🏿‍♂️
    🚶‍♀️\t1\t0\t女行人\t女|徒步|漫步|缓行|走|走路|路人\twoman walking\tamble|gait|hike|man|pace|pedestrian|stride|stroll|walk|walking|woman\t🚶🏻‍♀️ 🚶🏼‍♀️ 🚶🏽‍♀️ 🚶🏾‍♀️ 🚶🏿‍♀️
    🚶‍➡️\t1\t0\t行人: 面向右边\t压马路|徒步|散步|昂首阔步|竞走|行人|行走的人|走路|远足|闲逛|面向右边\tperson walking: facing right\tamble|facing|gait|hike|man|pace|pedestrian|person|right|stride|stroll|walk|walking\t🚶🏻‍➡️ 🚶🏼‍➡️ 🚶🏽‍➡️ 🚶🏾‍➡️ 🚶🏿‍➡️
    🚶‍♀️‍➡️\t1\t0\t女行人: 面向右边\t女|女行人|徒步|漫步|缓行|走|走路|路人|面向右边\twoman walking: facing right\tamble|facing|gait|hike|man|pace|pedestrian|right|stride|stroll|walk|walking|woman\t🚶🏻‍♀️‍➡️ 🚶🏼‍♀️‍➡️ 🚶🏽‍♀️‍➡️ 🚶🏾‍♀️‍➡️ 🚶🏿‍♀️‍➡️
    🚶‍♂️‍➡️\t1\t0\t男行人: 面向右边\t徒步|男|男行人|走路|面向右边\tman walking: facing right\tamble|facing|gait|hike|man|pace|pedestrian|right|stride|stroll|walk|walking\t🚶🏻‍♂️‍➡️ 🚶🏼‍♂️‍➡️ 🚶🏽‍♂️‍➡️ 🚶🏾‍♂️‍➡️ 🚶🏿‍♂️‍➡️
    🧍\t1\t0\t站立者\t人物|站着|站着的人|站立\tperson standing\tperson|stand|standing\t🧍🏻 🧍🏼 🧍🏽 🧍🏾 🧍🏿
    🧍‍♂️\t1\t0\t站立的男人\t男|站着|站立\tman standing\tman|stand|standing\t🧍🏻‍♂️ 🧍🏼‍♂️ 🧍🏽‍♂️ 🧍🏾‍♂️ 🧍🏿‍♂️
    🧍‍♀️\t1\t0\t站立的女人\t女|站着|站立\twoman standing\tstand|standing|woman\t🧍🏻‍♀️ 🧍🏼‍♀️ 🧍🏽‍♀️ 🧍🏾‍♀️ 🧍🏿‍♀️
    🧎\t1\t0\t下跪者\t下跪|跪下|跪坐\tperson kneeling\tkneel|kneeling|knees|person\t🧎🏻 🧎🏼 🧎🏽 🧎🏾 🧎🏿
    🧎‍♂️\t1\t0\t跪下的男人\t下跪|男|跪坐\tman kneeling\tkneel|kneeling|knees|man\t🧎🏻‍♂️ 🧎🏼‍♂️ 🧎🏽‍♂️ 🧎🏾‍♂️ 🧎🏿‍♂️
    🧎‍♀️\t1\t0\t跪下的女人\t下跪|女|跪坐\twoman kneeling\tkneel|kneeling|knees|woman\t🧎🏻‍♀️ 🧎🏼‍♀️ 🧎🏽‍♀️ 🧎🏾‍♀️ 🧎🏿‍♀️
    🧎‍➡️\t1\t0\t下跪者: 面向右边\t下跪|下跪者|跪下|跪坐|面向右边\tperson kneeling: facing right\tfacing|kneel|kneeling|knees|person|right\t🧎🏻‍➡️ 🧎🏼‍➡️ 🧎🏽‍➡️ 🧎🏾‍➡️ 🧎🏿‍➡️
    🧎‍♀️‍➡️\t1\t0\t跪下的女人: 面向右边\t下跪|女|跪下的女人|跪坐|面向右边\twoman kneeling: facing right\tfacing|kneel|kneeling|knees|right|woman\t🧎🏻‍♀️‍➡️ 🧎🏼‍♀️‍➡️ 🧎🏽‍♀️‍➡️ 🧎🏾‍♀️‍➡️ 🧎🏿‍♀️‍➡️
    🧎‍♂️‍➡️\t1\t0\t跪下的男人: 面向右边\t下跪|男|跪下的男人|跪坐|面向右边\tman kneeling: facing right\tfacing|kneel|kneeling|knees|man|right\t🧎🏻‍♂️‍➡️ 🧎🏼‍♂️‍➡️ 🧎🏽‍♂️‍➡️ 🧎🏾‍♂️‍➡️ 🧎🏿‍♂️‍➡️
    🧑‍🦯\t1\t0\t拄盲杖的人\t无障碍|盲\tperson with white cane\taccessibility|blind|cane|person|probing|white\t🧑🏻‍🦯 🧑🏼‍🦯 🧑🏽‍🦯 🧑🏾‍🦯 🧑🏿‍🦯
    🧑‍🦯‍➡️\t1\t0\t拄盲杖的人: 面向右边\t拄盲杖的人|无障碍|盲|面向右边\tperson with white cane: facing right\taccessibility|blind|cane|facing|person|probing|right|white\t🧑🏻‍🦯‍➡️ 🧑🏼‍🦯‍➡️ 🧑🏽‍🦯‍➡️ 🧑🏾‍🦯‍➡️ 🧑🏿‍🦯‍➡️
    👨‍🦯\t1\t0\t拄盲杖的男人\t拐杖|无障碍|男|男人|男子|盲|盲人\tman with white cane\taccessibility|blind|cane|man|probing|white\t👨🏻‍🦯 👨🏼‍🦯 👨🏽‍🦯 👨🏾‍🦯 👨🏿‍🦯
    👨‍🦯‍➡️\t1\t0\t拄盲杖的男人: 面向右边\t拄盲杖的男人|拐杖|无障碍|男|男人|男子|盲|盲人|面向右边\tman with white cane: facing right\taccessibility|blind|cane|facing|man|probing|right|white\t👨🏻‍🦯‍➡️ 👨🏼‍🦯‍➡️ 👨🏽‍🦯‍➡️ 👨🏾‍🦯‍➡️ 👨🏿‍🦯‍➡️
    👩‍🦯\t1\t0\t拄盲杖的女人\t女|女人|女性|拐杖|无障碍|盲|盲人\twoman with white cane\taccessibility|blind|cane|probing|white|woman\t👩🏻‍🦯 👩🏼‍🦯 👩🏽‍🦯 👩🏾‍🦯 👩🏿‍🦯
    👩‍🦯‍➡️\t1\t0\t拄盲杖的女人: 面向右边\t女|女人|女性|拄盲杖的女人|拐杖|无障碍|盲|盲人|面向右边\twoman with white cane: facing right\taccessibility|blind|cane|facing|probing|right|white|woman\t👩🏻‍🦯‍➡️ 👩🏼‍🦯‍➡️ 👩🏽‍🦯‍➡️ 👩🏾‍🦯‍➡️ 👩🏿‍🦯‍➡️
    🧑‍🦼\t1\t0\t坐电动轮椅的人\t无障碍|轮椅\tperson in motorized wheelchair\taccessibility|motorized|person|wheelchair\t🧑🏻‍🦼 🧑🏼‍🦼 🧑🏽‍🦼 🧑🏾‍🦼 🧑🏿‍🦼
    🧑‍🦼‍➡️\t1\t0\t坐电动轮椅的人: 面向右边\t坐电动轮椅的人|无障碍|轮椅|面向右边\tperson in motorized wheelchair: facing right\taccessibility|facing|motorized|person|right|wheelchair\t🧑🏻‍🦼‍➡️ 🧑🏼‍🦼‍➡️ 🧑🏽‍🦼‍➡️ 🧑🏾‍🦼‍➡️ 🧑🏿‍🦼‍➡️
    👨‍🦼\t1\t0\t坐电动轮椅的男人\t无障碍|电动|男|男人|男子|轮椅\tman in motorized wheelchair\taccessibility|man|motorized|wheelchair\t👨🏻‍🦼 👨🏼‍🦼 👨🏽‍🦼 👨🏾‍🦼 👨🏿‍🦼
    👨‍🦼‍➡️\t1\t0\t坐电动轮椅的男人: 面向右边\t坐电动轮椅的男人|无障碍|电动|男|男人|男子|轮椅|面向右边\tman in motorized wheelchair: facing right\taccessibility|facing|man|motorized|right|wheelchair\t👨🏻‍🦼‍➡️ 👨🏼‍🦼‍➡️ 👨🏽‍🦼‍➡️ 👨🏾‍🦼‍➡️ 👨🏿‍🦼‍➡️
    👩‍🦼\t1\t0\t坐电动轮椅的女人\t女|女人|女子|无障碍|电动|轮椅\twoman in motorized wheelchair\taccessibility|motorized|wheelchair|woman\t👩🏻‍🦼 👩🏼‍🦼 👩🏽‍🦼 👩🏾‍🦼 👩🏿‍🦼
    👩‍🦼‍➡️\t1\t0\t坐电动轮椅的女人: 面向右边\t坐电动轮椅的女人|女|女人|女子|无障碍|电动|轮椅|面向右边\twoman in motorized wheelchair: facing right\taccessibility|facing|motorized|right|wheelchair|woman\t👩🏻‍🦼‍➡️ 👩🏼‍🦼‍➡️ 👩🏽‍🦼‍➡️ 👩🏾‍🦼‍➡️ 👩🏿‍🦼‍➡️
    🧑‍🦽\t1\t0\t坐手动轮椅的人\t无障碍|轮椅\tperson in manual wheelchair\taccessibility|manual|person|wheelchair\t🧑🏻‍🦽 🧑🏼‍🦽 🧑🏽‍🦽 🧑🏾‍🦽 🧑🏿‍🦽
    🧑‍🦽‍➡️\t1\t0\t坐手动轮椅的人: 面向右边\t坐手动轮椅的人|无障碍|轮椅|面向右边\tperson in manual wheelchair: facing right\taccessibility|facing|manual|person|right|wheelchair\t🧑🏻‍🦽‍➡️ 🧑🏼‍🦽‍➡️ 🧑🏽‍🦽‍➡️ 🧑🏾‍🦽‍➡️ 🧑🏿‍🦽‍➡️
    👨‍🦽\t1\t0\t坐手动轮椅的男人\t手动|无障碍|男|男人|男子|轮椅\tman in manual wheelchair\taccessibility|man|manual|wheelchair\t👨🏻‍🦽 👨🏼‍🦽 👨🏽‍🦽 👨🏾‍🦽 👨🏿‍🦽
    👨‍🦽‍➡️\t1\t0\t坐手动轮椅的男人: 面向右边\t坐手动轮椅的男人|手动|无障碍|男|男人|男子|轮椅|面向右边\tman in manual wheelchair: facing right\taccessibility|facing|man|manual|right|wheelchair\t👨🏻‍🦽‍➡️ 👨🏼‍🦽‍➡️ 👨🏽‍🦽‍➡️ 👨🏾‍🦽‍➡️ 👨🏿‍🦽‍➡️
    👩‍🦽\t1\t0\t坐手动轮椅的女人\t女|女人|女子|手动|无障碍|轮椅\twoman in manual wheelchair\taccessibility|manual|wheelchair|woman\t👩🏻‍🦽 👩🏼‍🦽 👩🏽‍🦽 👩🏾‍🦽 👩🏿‍🦽
    👩‍🦽‍➡️\t1\t0\t坐手动轮椅的女人: 面向右边\t坐手动轮椅的女人|女|女人|女子|手动|无障碍|轮椅|面向右边\twoman in manual wheelchair: facing right\taccessibility|facing|manual|right|wheelchair|woman\t👩🏻‍🦽‍➡️ 👩🏼‍🦽‍➡️ 👩🏽‍🦽‍➡️ 👩🏾‍🦽‍➡️ 👩🏿‍🦽‍➡️
    🏃\t1\t0\t跑步者\t匆忙|向前冲|奔跑|快跑|赛跑|跑步|跑路|闪人|马拉松\tperson running\tfast|hurry|marathon|move|person|quick|race|racing|run|rush|speed\t🏃🏻 🏃🏼 🏃🏽 🏃🏾 🏃🏿
    🏃‍♂️\t1\t0\t男生跑步\t男|跑|马拉松\tman running\tfast|hurry|man|marathon|move|quick|race|racing|run|rush|speed\t🏃🏻‍♂️ 🏃🏼‍♂️ 🏃🏽‍♂️ 🏃🏾‍♂️ 🏃🏿‍♂️
    🏃‍♀️\t1\t0\t女生跑步\t冲刺|女|比赛|跑|跑步|马拉松\twoman running\tfast|hurry|marathon|move|quick|race|racing|run|rush|speed|woman\t🏃🏻‍♀️ 🏃🏼‍♀️ 🏃🏽‍♀️ 🏃🏾‍♀️ 🏃🏿‍♀️
    🏃‍➡️\t1\t0\t跑步者: 面向右边\t匆忙|向前冲|奔跑|快跑|赛跑|跑步|跑步者|跑路|闪人|面向右边|马拉松\tperson running: facing right\tfacing|fast|hurry|marathon|move|person|quick|race|racing|right|run|rush|speed\t🏃🏻‍➡️ 🏃🏼‍➡️ 🏃🏽‍➡️ 🏃🏾‍➡️ 🏃🏿‍➡️
    🏃‍♀️‍➡️\t1\t0\t女生跑步: 面向右边\t冲刺|女|女生跑步|比赛|跑|跑步|面向右边|马拉松\twoman running: facing right\tfacing|fast|hurry|marathon|move|quick|race|racing|right|run|rush|speed|woman\t🏃🏻‍♀️‍➡️ 🏃🏼‍♀️‍➡️ 🏃🏽‍♀️‍➡️ 🏃🏾‍♀️‍➡️ 🏃🏿‍♀️‍➡️
    🏃‍♂️‍➡️\t1\t0\t男生跑步: 面向右边\t男|男生跑步|跑|面向右边|马拉松\tman running: facing right\tfacing|fast|hurry|man|marathon|move|quick|race|racing|right|run|rush|speed\t🏃🏻‍♂️‍➡️ 🏃🏼‍♂️‍➡️ 🏃🏽‍♂️‍➡️ 🏃🏾‍♂️‍➡️ 🏃🏿‍♂️‍➡️
    💃\t1\t0\t跳舞的女人\t优雅|佛拉门戈|女人|女舞者|探戈|舞者|萨尔萨舞|跳舞\twoman dancing\tdance|dancer|dancing|elegant|festive|flair|flamenco|groove|let’s|salsa|tango|woman\t💃🏻 💃🏼 💃🏽 💃🏾 💃🏿
    🕺\t1\t0\t跳舞的男人\t佛拉门戈|男人|男舞者|舞者|跳舞\tman dancing\tdance|dancer|dancing|elegant|festive|flair|flamenco|groove|let’s|man|salsa|tango\t🕺🏻 🕺🏼 🕺🏽 🕺🏾 🕺🏿
    🕴️\t1\t0\t西装革履的人\t商务|正装|男|西装革履\tperson in suit levitating\tbusiness|levitating|person|suit\t🕴🏻 🕴🏼 🕴🏽 🕴🏾 🕴🏿
    👯\t1\t0\t戴兔耳朵的人\t兔子服|兔耳朵|双人舞|双胞胎|同好|永远的好朋友|派对|灵魂伴侣|聚会|舞者|跳舞|闺蜜\tpeople with bunny ears\tbestie|bff|bunny|counterpart|dancer|double|ear|identical|pair|party|partying|people|soulmate|twin|twinsies\t👯🏻 👯🏼 👯🏽 👯🏾 👯🏿
    👯‍♂️\t1\t0\t兔先生\t兔耳朵|同好|永远的好朋友|派对|男生派对|聚会|跳舞\tmen with bunny ears\tbestie|bff|bunny|counterpart|dancer|double|ear|identical|men|pair|party|partying|people|soulmate|twin|twinsies\t👯🏻‍♂️ 👯🏼‍♂️ 👯🏽‍♂️ 👯🏾‍♂️ 👯🏿‍♂️
    👯‍♀️\t1\t0\t兔女郎\t兔耳朵|女生派对|派对|聚会|跳舞\twomen with bunny ears\tbestie|bff|bunny|counterpart|dancer|double|ear|identical|pair|party|partying|people|soulmate|twin|twinsies|women\t👯🏻‍♀️ 👯🏼‍♀️ 👯🏽‍♀️ 👯🏾‍♀️ 👯🏿‍♀️
    🧖\t1\t0\t蒸房里的人\t在桑拿间的人|放松|桑拿|桑拿浴|蒸房|蒸气漫溢|蒸汽浴\tperson in steamy room\tday|luxurious|pamper|person|relax|room|sauna|spa|steam|steambath|unwind\t🧖🏻 🧖🏼 🧖🏽 🧖🏾 🧖🏿
    🧖‍♂️\t1\t0\t蒸房里的男人\t桑拿|男性桑拿\tman in steamy room\tday|luxurious|man|pamper|relax|room|sauna|spa|steam|steambath|unwind\t🧖🏻‍♂️ 🧖🏼‍♂️ 🧖🏽‍♂️ 🧖🏾‍♂️ 🧖🏿‍♂️
    🧖‍♀️\t1\t0\t蒸房里的女人\t女性桑拿|桑拿\twoman in steamy room\tday|luxurious|pamper|relax|room|sauna|spa|steam|steambath|unwind|woman\t🧖🏻‍♀️ 🧖🏼‍♀️ 🧖🏽‍♀️ 🧖🏾‍♀️ 🧖🏿‍♀️
    🧗\t1\t0\t攀爬的人\t向上爬的人|攀岩|攀岩者|爬山|登山|登山者\tperson climbing\tclimb|climber|climbing|mountain|person|rock|scale|up\t🧗🏻 🧗🏼 🧗🏽 🧗🏾 🧗🏿
    🧗‍♂️\t1\t0\t攀爬的男人\t登山者\tman climbing\tclimb|climber|climbing|man|mountain|rock|scale|up\t🧗🏻‍♂️ 🧗🏼‍♂️ 🧗🏽‍♂️ 🧗🏾‍♂️ 🧗🏿‍♂️
    🧗‍♀️\t1\t0\t攀爬的女人\t登山者\twoman climbing\tclimb|climber|climbing|mountain|rock|scale|up|woman\t🧗🏻‍♀️ 🧗🏼‍♀️ 🧗🏽‍♀️ 🧗🏾‍♀️ 🧗🏿‍♀️
    🤺\t1\t0\t击剑选手\t人|体育|击剑|剑\tperson fencing\tfencer|fencing|person|sword\t
    🏇\t1\t0\t赛马\t三冠|赛马骑师|马|骑师|骑马\thorse racing\thorse|jockey|racehorse|racing|riding|sport\t🏇🏻 🏇🏼 🏇🏽 🏇🏾 🏇🏿
    ⛷️\t1\t0\t滑雪的人\t滑雪|雪\tskier\tski|snow\t
    🏂️\t1\t0\t滑雪板\t单板|单板滑雪|滑雪|雪\tsnowboarder\tski|snow|snowboard|sport\t🏂🏻 🏂🏼 🏂🏽 🏂🏾 🏂🏿
    🏌️\t1\t0\t打高尔夫的人\tpga|小鸟球|推杆进球|球|球座|球穴区|球童|职业高尔夫协会|运动|高尔夫\tperson golfing\tball|birdie|caddy|driving|golf|golfing|green|person|pga|putt|range|tee\t🏌🏻 🏌🏼 🏌🏽 🏌🏾 🏌🏿
    🏌️‍♂️\t1\t0\t男生打高尔夫\t男|高尔夫\tman golfing\tball|birdie|caddy|driving|golf|golfing|green|man|pga|putt|range|tee\t🏌🏻‍♂️ 🏌🏼‍♂️ 🏌🏽‍♂️ 🏌🏾‍♂️ 🏌🏿‍♂️
    🏌️‍♀️\t1\t0\t女生打高尔夫\t女|高尔夫|高尔夫练球场\twoman golfing\tball|birdie|caddy|driving|golf|golfing|green|pga|putt|range|tee|woman\t🏌🏻‍♀️ 🏌🏼‍♀️ 🏌🏽‍♀️ 🏌🏾‍♀️ 🏌🏿‍♀️
    🏄️\t1\t0\t冲浪\t冲浪的人|冲浪者|波浪|海上运动|海洋|海滩|涌浪|网上冲浪|运动\tperson surfing\tbeach|ocean|person|sport|surf|surfer|surfing|swell|waves\t🏄🏻 🏄🏼 🏄🏽 🏄🏾 🏄🏿
    🏄‍♂️\t1\t0\t男生冲浪\t冲浪|男\tman surfing\tbeach|man|ocean|sport|surf|surfer|surfing|swell|waves\t🏄🏻‍♂️ 🏄🏼‍♂️ 🏄🏽‍♂️ 🏄🏾‍♂️ 🏄🏿‍♂️
    🏄‍♀️\t1\t0\t女生冲浪\t冲浪|女|海滩\twoman surfing\tbeach|ocean|person|sport|surf|surfer|surfing|swell|waves\t🏄🏻‍♀️ 🏄🏼‍♀️ 🏄🏽‍♀️ 🏄🏾‍♀️ 🏄🏿‍♀️
    🚣\t1\t0\t划艇\t划桨|划船运动|木筏|河|泛舟湖上|湖|独木舟|船|钓鱼\tperson rowing boat\tboat|canoe|cruise|fishing|lake|oar|paddle|person|raft|river|row|rowboat|rowing\t🚣🏻 🚣🏼 🚣🏽 🚣🏾 🚣🏿
    🚣‍♂️\t1\t0\t男生划船\t划船|划艇|男|船\tman rowing boat\tboat|canoe|cruise|fishing|lake|man|oar|paddle|raft|river|row|rowboat|rowing\t🚣🏻‍♂️ 🚣🏼‍♂️ 🚣🏽‍♂️ 🚣🏾‍♂️ 🚣🏿‍♂️
    🚣‍♀️\t1\t0\t女生划船\t划船|划艇|女|船\twoman rowing boat\tboat|canoe|cruise|fishing|lake|oar|paddle|raft|river|row|rowboat|rowing|woman\t🚣🏻‍♀️ 🚣🏼‍♀️ 🚣🏽‍♀️ 🚣🏾‍♀️ 🚣🏿‍♀️
    🏊️\t1\t0\t游泳\t游泳的人|游泳者|自由泳|运动|铁人三项\tperson swimming\tfreestyle|person|sport|swim|swimmer|swimming|triathlon\t🏊🏻 🏊🏼 🏊🏽 🏊🏾 🏊🏿
    🏊‍♂️\t1\t0\t男生游泳\t游泳|男\tman swimming\tfreestyle|man|sport|swim|swimmer|swimming|triathlon\t🏊🏻‍♂️ 🏊🏼‍♂️ 🏊🏽‍♂️ 🏊🏾‍♂️ 🏊🏿‍♂️
    🏊‍♀️\t1\t0\t女生游泳\t女|游泳\twoman swimming\tfreestyle|man|sport|swim|swimmer|swimming|triathlon\t🏊🏻‍♀️ 🏊🏼‍♀️ 🏊🏽‍♀️ 🏊🏾‍♀️ 🏊🏿‍♀️
    ⛹️\t1\t0\t玩球\t体育|全网无阻|打球|游戏|玩|球|篮球|篮球运动员|罚球|运动|运球|锦标赛\tperson bouncing ball\tathletic|ball|basketball|bouncing|championship|dribble|net|person|player|throw\t⛹🏻 ⛹🏼 ⛹🏽 ⛹🏾 ⛹🏿
    ⛹️‍♂️\t1\t0\t男生玩球\t球|男\tman bouncing ball\tathletic|ball|basketball|bouncing|championship|dribble|man|net|player|throw\t⛹🏻‍♂️ ⛹🏼‍♂️ ⛹🏽‍♂️ ⛹🏾‍♂️ ⛹🏿‍♂️
    ⛹️‍♀️\t1\t0\t女生玩球\t女|女生打篮球|游戏|玩|球|篮球\twoman bouncing ball\tathletic|ball|basketball|bouncing|championship|dribble|net|player|throw|woman\t⛹🏻‍♀️ ⛹🏼‍♀️ ⛹🏽‍♀️ ⛹🏾‍♀️ ⛹🏿‍♀️
    🏋️\t1\t0\t举重\t举重的人|举重运动员|举铁|健美者|力量举重|杠铃|硬拉|训练|运动\tperson lifting weights\tbarbell|bodybuilder|deadlift|lifter|lifting|person|powerlifting|weight|weightlifter|weights|workout\t🏋🏻 🏋🏼 🏋🏽 🏋🏾 🏋🏿
    🏋️‍♂️\t1\t0\t男生举重\t举重|男\tman lifting weights\tbarbell|bodybuilder|deadlift|lifter|lifting|man|powerlifting|weight|weightlifter|weights|workout\t🏋🏻‍♂️ 🏋🏼‍♂️ 🏋🏽‍♂️ 🏋🏾‍♂️ 🏋🏿‍♂️
    🏋️‍♀️\t1\t0\t女生举重\t举重|女|训练\twoman lifting weights\tbarbell|bodybuilder|deadlift|lifter|lifting|powerlifting|weight|weightlifter|weights|woman|workout\t🏋🏻‍♀️ 🏋🏼‍♀️ 🏋🏽‍♀️ 🏋🏾‍♀️ 🏋🏿‍♀️
    🚴\t1\t0\t骑自行车\t单车|脚踏车|自行车|自行车赛|自行车骑士|运动|骑单车|骑脚踏车者|骑自行车的人|骑自行车者\tperson biking\tbicycle|bicyclist|bike|biking|cycle|cyclist|person|riding|sport\t🚴🏻 🚴🏼 🚴🏽 🚴🏾 🚴🏿
    🚴‍♂️\t1\t0\t男生骑自行车\t单车|男|自行车|骑车\tman biking\tbicycle|bicyclist|bike|biking|cycle|cyclist|man|riding|sport\t🚴🏻‍♂️ 🚴🏼‍♂️ 🚴🏽‍♂️ 🚴🏾‍♂️ 🚴🏿‍♂️
    🚴‍♀️\t1\t0\t女生骑自行车\t单车|女|女生骑车|自行车|骑车\twoman biking\tbicycle|bicyclist|bike|biking|cycle|cyclist|riding|sport|woman\t🚴🏻‍♀️ 🚴🏼‍♀️ 🚴🏽‍♀️ 🚴🏾‍♀️ 🚴🏿‍♀️
    🚵\t1\t0\t骑山地车\t体育竞技|单车|山|山地自行车|山地车|山地骑行的人|自行车|运动|骑山地车的人|骑自行车|骑自行车者\tperson mountain biking\tbicycle|bicyclist|bike|biking|cycle|cyclist|mountain|person|riding|sport\t🚵🏻 🚵🏼 🚵🏽 🚵🏾 🚵🏿
    🚵‍♂️\t1\t0\t男生骑山地车\t单车|山地车|男|自行车|骑山地车的人\tman mountain biking\tbicycle|bicyclist|bike|biking|cycle|cyclist|man|mountain|riding|sport\t🚵🏻‍♂️ 🚵🏼‍♂️ 🚵🏽‍♂️ 🚵🏾‍♂️ 🚵🏿‍♂️
    🚵‍♀️\t1\t0\t女生骑山地车\t单车|女|山地车|自行车|骑车\twoman mountain biking\tbicycle|bicyclist|bike|biking|cycle|cyclist|mountain|riding|sport|woman\t🚵🏻‍♀️ 🚵🏼‍♀️ 🚵🏽‍♀️ 🚵🏾‍♀️ 🚵🏿‍♀️
    🤸\t1\t0\t侧手翻\t人|体操|体育|兴奋|快乐|杂技|活泼|翻筋斗\tperson cartwheeling\tactive|cartwheel|cartwheeling|excited|flip|gymnastics|happy|person|somersault\t🤸🏻 🤸🏼 🤸🏽 🤸🏾 🤸🏿
    🤸‍♂️\t1\t0\t男生侧手翻\t体操|侧手翻|兴奋|快乐|杂技|活泼|男|男子侧手翻|翻筋斗\tman cartwheeling\tactive|cartwheel|cartwheeling|excited|flip|gymnastics|happy|man|somersault\t🤸🏻‍♂️ 🤸🏼‍♂️ 🤸🏽‍♂️ 🤸🏾‍♂️ 🤸🏿‍♂️
    🤸‍♀️\t1\t0\t女生侧手翻\t体操|侧手翻|兴奋|女|女子侧手翻|快乐|杂技|活泼|翻筋斗\twoman cartwheeling\tactive|cartwheel|cartwheeling|excited|flip|gymnastics|happy|somersault|woman\t🤸🏻‍♀️ 🤸🏼‍♀️ 🤸🏽‍♀️ 🤸🏾‍♀️ 🤸🏿‍♀️
    🤼\t1\t0\t摔跤选手\t人|体育|对决|打架|搏斗|摔跤|摔跤比赛|擂台争霸|运动\tpeople wrestling\tcombat|duel|grapple|people|ring|tournament|wrestle|wrestling\t🤼🏻 🤼🏼 🤼🏽 🤼🏾 🤼🏿
    🤼‍♂️\t1\t0\t男生摔跤\t对决|打架|搏斗|摔跤|摔跤比赛|擂台争霸|男|男子摔跤|运动\tmen wrestling\tcombat|duel|grapple|men|ring|tournament|wrestle|wrestling\t🤼🏻‍♂️ 🤼🏼‍♂️ 🤼🏽‍♂️ 🤼🏾‍♂️ 🤼🏿‍♂️
    🤼‍♀️\t1\t0\t女生摔跤\t女|女子摔跤|对决|打架|搏斗|摔跤|摔跤比赛|擂台争霸|运动\twomen wrestling\tcombat|duel|grapple|ring|tournament|women|wrestle|wrestling\t🤼🏻‍♀️ 🤼🏼‍♀️ 🤼🏽‍♀️ 🤼🏾‍♀️ 🤼🏿‍♀️
    🤽\t1\t0\t水球\t人|体育|水上足球|水上运动|游泳|马可波罗游戏\tperson playing water polo\tperson|playing|polo|sport|swimming|water|waterpolo\t🤽🏻 🤽🏼 🤽🏽 🤽🏾 🤽🏿
    🤽‍♂️\t1\t0\t男生玩水球\t水上足球|水上运动|水球|游泳|男|男子玩水球|马可波罗游戏\tman playing water polo\tman|playing|polo|sport|swimming|water|waterpolo\t🤽🏻‍♂️ 🤽🏼‍♂️ 🤽🏽‍♂️ 🤽🏾‍♂️ 🤽🏿‍♂️
    🤽‍♀️\t1\t0\t女生玩水球\t女|女子玩水球|水上足球|水上运动|水球|游泳|马可波罗游戏\twoman playing water polo\tplaying|polo|sport|swimming|water|waterpolo|woman\t🤽🏻‍♀️ 🤽🏼‍♀️ 🤽🏽‍♀️ 🤽🏾‍♀️ 🤽🏿‍♀️
    🤾\t1\t0\t手球\t人|体育|投|投球|抛|接球|犯规投球|球|运动|高球\tperson playing handball\tathletics|ball|catch|chuck|handball|hurl|lob|person|pitch|playing|sport|throw|toss\t🤾🏻 🤾🏼 🤾🏽 🤾🏾 🤾🏿
    🤾‍♂️\t1\t0\t男生玩手球\t墙手球|手球|男\tman playing handball\tathletics|ball|catch|chuck|handball|hurl|lob|man|pitch|playing|sport|throw|toss\t🤾🏻‍♂️ 🤾🏼‍♂️ 🤾🏽‍♂️ 🤾🏾‍♂️ 🤾🏿‍♂️
    🤾‍♀️\t1\t0\t女生玩手球\t女|女子玩手球|手球|扔|投球|抛|接球|犯规投球|球|运动|高球\twoman playing handball\tathletics|ball|catch|chuck|handball|hurl|lob|pitch|playing|sport|throw|toss|woman\t🤾🏻‍♀️ 🤾🏼‍♀️ 🤾🏽‍♀️ 🤾🏾‍♀️ 🤾🏿‍♀️
    🤹\t1\t0\t抛接杂耍\t一心多用|人|平衡|平衡艺术|抛接|抛接球|操纵|杂技|杂耍|表演\tperson juggling\tact|balance|balancing|handle|juggle|juggling|manage|multitask|person|skill\t🤹🏻 🤹🏼 🤹🏽 🤹🏾 🤹🏿
    🤹‍♂️\t1\t0\t男生抛接杂耍\t一心多用|平衡艺术|抛接球|操纵|杂技|杂耍|男|男子|颠球\tman juggling\tact|balance|balancing|handle|juggle|juggling|man|manage|multitask|skill\t🤹🏻‍♂️ 🤹🏼‍♂️ 🤹🏽‍♂️ 🤹🏾‍♂️ 🤹🏿‍♂️
    🤹‍♀️\t1\t0\t女生抛接杂耍\t女|杂技|杂耍|颠球\twoman juggling\tact|balance|balancing|handle|juggle|juggling|manage|multitask|skill|woman\t🤹🏻‍♀️ 🤹🏼‍♀️ 🤹🏽‍♀️ 🤹🏾‍♀️ 🤹🏿‍♀️
    🧘\t1\t0\t盘腿的人\t冥想|放松|沉思|瑜伽|盘腿而坐|禅|莲花坐的人\tperson in lotus position\tcross|legged|legs|lotus|meditation|peace|person|position|relax|serenity|yoga|yogi|zen\t🧘🏻 🧘🏼 🧘🏽 🧘🏾 🧘🏿
    🧘‍♂️\t1\t0\t盘腿的男人\t和尚|瑜伽男\tman in lotus position\tcross|legged|legs|lotus|man|meditation|peace|position|relax|serenity|yoga|yogi|zen\t🧘🏻‍♂️ 🧘🏼‍♂️ 🧘🏽‍♂️ 🧘🏾‍♂️ 🧘🏿‍♂️
    🧘‍♀️\t1\t0\t盘腿的女人\t尼姑|比丘尼|瑜伽女\twoman in lotus position\tcross|legged|legs|lotus|meditation|peace|position|relax|serenity|woman|yoga|yogi|zen\t🧘🏻‍♀️ 🧘🏼‍♀️ 🧘🏽‍♀️ 🧘🏾‍♀️ 🧘🏿‍♀️
    🛀\t1\t0\t洗澡的人\t洗澡|浴盆|浴缸|澡盆|盆浴\tperson taking bath\tbath|bathtub|person|taking|tub\t🛀🏻 🛀🏼 🛀🏽 🛀🏾 🛀🏿
    🛌\t1\t0\t躺在床上的人\t入睡|夜里|宾馆|晚安|酒店\tperson in bed\tbed|bedtime|good|goodnight|hotel|nap|night|person|sleep|tired|zzz\t🛌🏻 🛌🏼 🛌🏽 🛌🏾 🛌🏿
    🧑‍🤝‍🧑\t1\t0\t手拉手的两个人\t两个人手牵手|人|情侣|手|手牵手的人|拉手|握手|牵手\tpeople holding hands\tbae|bestie|bff|couple|dating|flirt|friends|hand|hold|people|twins\t🧑🏻‍🤝‍🧑🏻 🧑🏼‍🤝‍🧑🏼 🧑🏽‍🤝‍🧑🏽 🧑🏾‍🤝‍🧑🏾 🧑🏿‍🤝‍🧑🏿
    👭\t1\t0\t手拉手的两个女人\t两个女人|好朋友|情侣|手拉手|朋友\twomen holding hands\tbae|bestie|bff|couple|dating|flirt|friends|girls|hand|hold|sisters|twins|women\t👭🏻 👭🏼 👭🏽 👭🏾 👭🏿
    👫\t1\t0\t手拉手的一男一女\t一男一女|情侣|手拉手|相恋\twoman and man holding hands\tbae|bestie|bff|couple|dating|flirt|friends|hand|hold|man|twins|woman\t👫🏻 👫🏼 👫🏽 👫🏾 👫🏿
    👬\t1\t0\t手拉手的两个男人\t两个男人|双子座|情侣|手拉手|朋友|黄道十二宫\tmen holding hands\tbae|bestie|bff|boys|brothers|couple|dating|flirt|friends|hand|hold|men|twins\t👬🏻 👬🏼 👬🏽 👬🏾 👬🏿
    💏\t1\t0\t亲吻\t宝贝|情侣|接吻|浪漫|约会\tkiss\tanniversary|babe|bae|couple|date|dating|heart|love|mwah|person|romance|together|xoxo\t💏🏻 💏🏼 💏🏽 💏🏾 💏🏿
    👩‍❤️‍💋‍👨\t1\t0\t亲吻: 女人男人\t亲吻|女人|宝贝|情侣|接吻|浪漫|男人|约会\tkiss: woman, man\tanniversary|babe|bae|couple|date|dating|heart|kiss|love|man|mwah|person|romance|together|woman|xoxo\t👩🏻‍❤️‍💋‍👨🏻 👩🏼‍❤️‍💋‍👨🏼 👩🏽‍❤️‍💋‍👨🏽 👩🏾‍❤️‍💋‍👨🏾 👩🏿‍❤️‍💋‍👨🏿
    👨‍❤️‍💋‍👨\t1\t0\t亲吻: 男人男人\t亲吻|宝贝|情侣|接吻|浪漫|男人|约会\tkiss: man, man\tanniversary|babe|bae|couple|date|dating|heart|kiss|love|man|mwah|person|romance|together|xoxo\t👨🏻‍❤️‍💋‍👨🏻 👨🏼‍❤️‍💋‍👨🏼 👨🏽‍❤️‍💋‍👨🏽 👨🏾‍❤️‍💋‍👨🏾 👨🏿‍❤️‍💋‍👨🏿
    👩‍❤️‍💋‍👩\t1\t0\t亲吻: 女人女人\t亲吻|女人|宝贝|情侣|接吻|浪漫|约会\tkiss: woman, woman\tanniversary|babe|bae|couple|date|dating|heart|kiss|love|mwah|person|romance|together|woman|xoxo\t👩🏻‍❤️‍💋‍👩🏻 👩🏼‍❤️‍💋‍👩🏼 👩🏽‍❤️‍💋‍👩🏽 👩🏾‍❤️‍💋‍👩🏾 👩🏿‍❤️‍💋‍👩🏿
    💑\t1\t0\t情侣\t恋爱|浪漫|红心|约会\tcouple with heart\tanniversary|babe|bae|couple|dating|heart|kiss|love|person|relationship|romance|together|you\t💑🏻 💑🏼 💑🏽 💑🏾 💑🏿
    👩‍❤️‍👨\t1\t0\t情侣: 女人男人\t女人|恋爱|情侣|浪漫|男人|红心|约会\tcouple with heart: woman, man\tanniversary|babe|bae|couple|dating|heart|kiss|love|man|person|relationship|romance|together|woman|you\t👩🏻‍❤️‍👨🏻 👩🏼‍❤️‍👨🏼 👩🏽‍❤️‍👨🏽 👩🏾‍❤️‍👨🏾 👩🏿‍❤️‍👨🏿
    👨‍❤️‍👨\t1\t0\t情侣: 男人男人\t恋爱|情侣|浪漫|男人|红心|约会\tcouple with heart: man, man\tanniversary|babe|bae|couple|dating|heart|kiss|love|man|person|relationship|romance|together|you\t👨🏻‍❤️‍👨🏻 👨🏼‍❤️‍👨🏼 👨🏽‍❤️‍👨🏽 👨🏾‍❤️‍👨🏾 👨🏿‍❤️‍👨🏿
    👩‍❤️‍👩\t1\t0\t情侣: 女人女人\t女人|恋爱|情侣|浪漫|红心|约会\tcouple with heart: woman, woman\tanniversary|babe|bae|couple|dating|heart|kiss|love|person|relationship|romance|together|woman|you\t👩🏻‍❤️‍👩🏻 👩🏼‍❤️‍👩🏼 👩🏽‍❤️‍👩🏽 👩🏾‍❤️‍👩🏾 👩🏿‍❤️‍👩🏿
    👨‍👩‍👦\t1\t0\t家庭: 男人女人男孩\t亲子|女人|家庭|父母和儿子|男人|男孩\tfamily: man, woman, boy\tboy|child|family|man|woman\t
    👨‍👩‍👧\t1\t0\t家庭: 男人女人女孩\t亲子|女人|女孩|家庭|父母和儿子|男人\tfamily: man, woman, girl\tchild|family|girl|man|woman\t
    👨‍👩‍👧‍👦\t1\t0\t家庭: 男人女人女孩男孩\t亲子|女人|女孩|家庭|父母和儿子|男人|男孩\tfamily: man, woman, girl, boy\tboy|child|family|girl|man|woman\t
    👨‍👩‍👦‍👦\t1\t0\t家庭: 男人女人男孩男孩\t亲子|女人|家庭|父母和儿子|男人|男孩\tfamily: man, woman, boy, boy\tboy|child|family|man|woman\t
    👨‍👩‍👧‍👧\t1\t0\t家庭: 男人女人女孩女孩\t亲子|女人|女孩|家庭|父母和儿子|男人\tfamily: man, woman, girl, girl\tchild|family|girl|man|woman\t
    👨‍👨‍👦\t1\t0\t家庭: 男人男人男孩\t亲子|家庭|父母和儿子|男人|男孩\tfamily: man, man, boy\tboy|child|family|man\t
    👨‍👨‍👧\t1\t0\t家庭: 男人男人女孩\t亲子|女孩|家庭|父母和儿子|男人\tfamily: man, man, girl\tchild|family|girl|man\t
    👨‍👨‍👧‍👦\t1\t0\t家庭: 男人男人女孩男孩\t亲子|女孩|家庭|父母和儿子|男人|男孩\tfamily: man, man, girl, boy\tboy|child|family|girl|man\t
    👨‍👨‍👦‍👦\t1\t0\t家庭: 男人男人男孩男孩\t亲子|家庭|父母和儿子|男人|男孩\tfamily: man, man, boy, boy\tboy|child|family|man\t
    👨‍👨‍👧‍👧\t1\t0\t家庭: 男人男人女孩女孩\t亲子|女孩|家庭|父母和儿子|男人\tfamily: man, man, girl, girl\tchild|family|girl|man\t
    👩‍👩‍👦\t1\t0\t家庭: 女人女人男孩\t亲子|女人|家庭|父母和儿子|男孩\tfamily: woman, woman, boy\tboy|child|family|woman\t
    👩‍👩‍👧\t1\t0\t家庭: 女人女人女孩\t亲子|女人|女孩|家庭|父母和儿子\tfamily: woman, woman, girl\tchild|family|girl|woman\t
    👩‍👩‍👧‍👦\t1\t0\t家庭: 女人女人女孩男孩\t亲子|女人|女孩|家庭|父母和儿子|男孩\tfamily: woman, woman, girl, boy\tboy|child|family|girl|woman\t
    👩‍👩‍👦‍👦\t1\t0\t家庭: 女人女人男孩男孩\t亲子|女人|家庭|父母和儿子|男孩\tfamily: woman, woman, boy, boy\tboy|child|family|woman\t
    👩‍👩‍👧‍👧\t1\t0\t家庭: 女人女人女孩女孩\t亲子|女人|女孩|家庭|父母和儿子\tfamily: woman, woman, girl, girl\tchild|family|girl|woman\t
    👨‍👦\t1\t0\t家庭: 男人男孩\t亲子|家庭|父母和儿子|男人|男孩\tfamily: man, boy\tboy|child|family|man\t
    👨‍👦‍👦\t1\t0\t家庭: 男人男孩男孩\t亲子|家庭|父母和儿子|男人|男孩\tfamily: man, boy, boy\tboy|child|family|man\t
    👨‍👧\t1\t0\t家庭: 男人女孩\t亲子|女孩|家庭|父母和儿子|男人\tfamily: man, girl\tchild|family|girl|man\t
    👨‍👧‍👦\t1\t0\t家庭: 男人女孩男孩\t亲子|女孩|家庭|父母和儿子|男人|男孩\tfamily: man, girl, boy\tboy|child|family|girl|man\t
    👨‍👧‍👧\t1\t0\t家庭: 男人女孩女孩\t亲子|女孩|家庭|父母和儿子|男人\tfamily: man, girl, girl\tchild|family|girl|man\t
    👩‍👦\t1\t0\t家庭: 女人男孩\t亲子|女人|家庭|父母和儿子|男孩\tfamily: woman, boy\tboy|child|family|woman\t
    👩‍👦‍👦\t1\t0\t家庭: 女人男孩男孩\t亲子|女人|家庭|父母和儿子|男孩\tfamily: woman, boy, boy\tboy|child|family|woman\t
    👩‍👧\t1\t0\t家庭: 女人女孩\t亲子|女人|女孩|家庭|父母和儿子\tfamily: woman, girl\tchild|family|girl|woman\t
    👩‍👧‍👦\t1\t0\t家庭: 女人女孩男孩\t亲子|女人|女孩|家庭|父母和儿子|男孩\tfamily: woman, girl, boy\tboy|child|family|girl|woman\t
    👩‍👧‍👧\t1\t0\t家庭: 女人女孩女孩\t亲子|女人|女孩|家庭|父母和儿子\tfamily: woman, girl, girl\tchild|family|girl|woman\t
    🗣️\t1\t0\t说话\t剪影|头|脸|讲话|说话头\tspeaking head\tface|head|silhouette|speak|speaking\t
    👤\t1\t0\t人像\t剪影|半身|半身像\tbust in silhouette\tbust|mysterious|shadow|silhouette\t
    👥\t1\t0\t双人像\t剪影|半身|半身像|朋友\tbusts in silhouette\tbff|bust|busts|everyone|friend|friends|people|silhouette\t
    🫂\t1\t0\t人的拥抱\t再见|友谊|告别|安慰|您好|感谢|抱抱|拥抱|爱\tpeople hugging\tcomfort|embrace|farewell|friendship|goodbye|hello|hug|hugging|love|people|thanks\t
    👪️\t1\t0\t家庭\t亲子|父母和儿子\tfamily\tchild\t
    🧑‍🧑‍🧒\t1\t0\t一孩家庭\t一孩|家庭|父母|独生子女\tfamily: adult, adult, child\tadult|child|family\t
    🧑‍🧑‍🧒‍🧒\t1\t0\t二孩家庭\t二孩|家庭|父母|非独生子女\tfamily: adult, adult, child, child\tadult|child|family\t
    🧑‍🧒\t1\t0\t单亲一孩家庭\t一孩|单亲|孩子|家庭\tfamily: adult, child\tadult|child|family\t
    🧑‍🧒‍🧒\t1\t0\t单亲二孩家庭\t二孩|单亲|孩子|家庭\tfamily: adult, child, child\tadult|child|family\t
    👣\t1\t0\t脚印\t在路上|赤脚|足迹\tfootprints\tbarefoot|clothing|footprint|omw|print|walk\t
    🫆\t1\t1\t指纹\t侦探|印迹|安全|犯罪|痕迹|神秘|线索|身份|鉴证\tfingerprint\tclue|crime|detective|forensics|identity|mystery|print|safety|trace\t
    🐵\t3\t0\t猴头\t动物|猴|猴子\tmonkey face\tanimal|banana|face|monkey\t
    🐒\t3\t0\t猴子\t猴\tmonkey\tanimal|banana\t
    🦍\t3\t0\t大猩猩\t动物\tgorilla\tanimal\t
    🦧\t3\t0\t红毛猩猩\t动物|猩猩|猴|猴子|猿\torangutan\tanimal|ape|monkey\t
    🐶\t3\t0\t狗脸\t宠物|小狗|汪星人|狗|脸\tdog face\tadorbs|animal|dog|face|pet|puppies|puppy\t
    🐕️\t3\t0\t狗\t动物|宠物|小狗|汪星人\tdog\tanimal|animals|dogs|pet\t
    🦮\t3\t0\t导盲犬\t指引|无障碍|盲|盲人\tguide dog\taccessibility|animal|blind|dog|guide\t
    🐕‍🦺\t3\t0\t服务犬\t工作犬|无障碍|服务|犬|狗|辅助\tservice dog\taccessibility|animal|assistance|dog|service\t
    🐩\t3\t0\t贵宾犬\t卷毛狗|毛茸茸|狗\tpoodle\tanimal|dog|fluffy\t
    🐺\t3\t0\t狼\t头|狼头|脸\twolf\tanimal|face\t
    🦊\t3\t0\t狐狸\t动物|头|狐狸的脸|脸\tfox\tanimal|face\t
    🦝\t3\t0\t浣熊\t动物|好奇|淘气|狡猾\traccoon\tanimal|curious|sly\t
    🐱\t3\t0\t猫脸\t宠物|猫|猫咪|脸\tcat face\tanimal|cat|face|kitten|kitty|pet\t
    🐈️\t3\t0\t猫\t宠物|小猫\tcat\tanimal|animals|cats|kitten|pet\t
    🐈‍⬛\t3\t0\t黑猫\t万圣节|不吉利|动物|喵|喵星人|猫|猫科|黑色\tblack cat\tanimal|black|cat|feline|halloween|meow|unlucky\t
    🦁\t3\t0\t狮子\t狮子头|狮子座|脸|黄道十二宫\tlion\talpha|animal|face|leo|mane|order|rawr|roar|safari|strong|zodiac\t
    🐯\t3\t0\t老虎头\t森林之王|老虎|脸\ttiger face\tanimal|big|cat|face|predator|tiger\t
    🐅\t3\t0\t老虎\t动物园|虎\ttiger\tanimal|big|cat|predator|zoo\t
    🐆\t3\t0\t豹子\t动物|猎豹|豹\tleopard\tanimal|big|cat|predator|zoo\t
    🐴\t3\t0\t马头\t盛装舞步|马\thorse face\tanimal|dressage|equine|face|farm|horse|horses\t
    🫎\t3\t0\t驼鹿\t动物|哺乳动物|鹿角|麋鹿\tmoose\talces|animal|antlers|elk|mammal\t
    🫏\t3\t0\t驴\t倔强|动物|哺乳动物|固执的|犟|驴子|骡|骡子\tdonkey\tanimal|ass|burro|hinny|mammal|mule|stubborn\t
    🐎\t3\t0\t马\t动物|比赛|赛马|骑马\thorse\tanimal|equestrian|farm|racehorse|racing\t
    🦄\t3\t0\t独角兽\t头|独角兽头|脸\tunicorn\tface\t
    🦓\t3\t0\t斑马\t条纹\tzebra\tanimal|stripe\t
    🦌\t3\t0\t鹿\t动物\tdeer\tanimal\t
    🦬\t3\t0\t大野牛\t动物|欧洲野牛|水牛|牛|牦牛|畜群|野牛\tbison\tanimal|buffalo|herd|wisent\t
    🐮\t3\t0\t奶牛头\t乳牛|奶牛|母牛|牛头|脸\tcow face\tanimal|cow|face|farm|milk|moo\t
    🐂\t3\t0\t公牛\t牛|金牛座|黄道十二宫\tox\tanimal|animals|bull|farm|taurus|zodiac\t
    🐃\t3\t0\t水牛\t水牛\twater buffalo\tanimal|buffalo|water|zoo\t
    🐄\t3\t0\t奶牛\t乳牛|牛\tcow\tanimal|animals|farm|milk|moo\t
    🐷\t3\t0\t猪头\t八戒|猪|脸\tpig face\tanimal|bacon|face|farm|pig|pork\t
    🐖\t3\t0\t猪\t培根|猪肉\tpig\tanimal|bacon|farm|pork|sow\t
    🐗\t3\t0\t野猪\t动物|猪\tboar\tanimal|pig\t
    🐽\t3\t0\t猪鼻子\t猪|脸|闻|鼻|鼻子\tpig nose\tanimal|face|farm|nose|pig|smell|snout\t
    🐏\t3\t0\t公羊\t白羊座|羊|雄性|黄道十二宫\tram\tanimal|aries|horns|male|sheep|zodiac|zoo\t
    🐑\t3\t0\t母羊\t咩|毛茸茸|绵羊|羊|羊毛|雌性\tewe\tanimal|baa|farm|female|fluffy|lamb|sheep|wool\t
    🐐\t3\t0\t山羊\t摩羯座|黄道十二宫\tgoat\tanimal|capricorn|farm|milk|zodiac\t
    🐪\t3\t0\t骆驼\t单峰|单峰驼|沙漠|驼峰\tcamel\tanimal|desert|dromedary|hump|one\t
    🐫\t3\t0\t双峰骆驼\t双峰|沙漠|骆驼\ttwo-hump camel\tanimal|bactrian|camel|desert|hump|two|two-hump\t
    🦙\t3\t0\t美洲鸵\t动物|原驼|小羊驼|无峰驼|羊毛|羊驼|骆马\tllama\talpaca|animal|guanaco|vicuña|wool\t
    🦒\t3\t0\t长颈鹿\t斑点\tgiraffe\tanimal|spots\t
    🐘\t3\t0\t大象\t动物|象\telephant\tanimal\t
    🦣\t3\t0\t猛犸\t动物|大型|有绒毛的|灭绝|猛犸象|长毛象|长牙\tmammoth\tanimal|extinction|large|tusk|wooly\t
    🦏\t3\t0\t犀牛\t动物\trhinoceros\tanimal\t
    🦛\t3\t0\t河马\t动物\thippopotamus\tanimal|hippo\t
    🐭\t3\t0\t老鼠头\t鼠\tmouse face\tanimal|face|mouse\t
    🐁\t3\t0\t老鼠\t耗子|鼠\tmouse\tanimal|animals\t
    🐀\t3\t0\t耗子\t鼠\trat\tanimal\t
    🐹\t3\t0\t仓鼠\t仓鼠头|啮齿|头|宠物|脸\thamster\tanimal|face|pet\t
    🐰\t3\t0\t兔子头\t兔|兔宝宝|宠物\trabbit face\tanimal|bunny|face|pet|rabbit\t
    🐇\t3\t0\t兔子\t兔|动物\trabbit\tanimal|bunny|pet\t
    🐿️\t3\t0\t松鼠\t花栗鼠|金花鼠\tchipmunk\tanimal|squirrel\t
    🦫\t3\t0\t海狸\t动物|大板牙|母畜\tbeaver\tanimal|dam|teeth\t
    🦔\t3\t0\t刺猬\t多刺\thedgehog\tanimal|spiny\t
    🦇\t3\t0\t蝙蝠\t吸血鬼\tbat\tanimal|vampire\t
    🐻\t3\t0\t熊\t低吼|头|灰熊|熊头|熊脸|脸\tbear\tanimal|face|grizzly|growl|honey\t
    🐻‍❄️\t3\t0\t北极熊\t北极|熊|白色\tpolar bear\tanimal|arctic|bear|polar|white\t
    🐨\t3\t0\t考拉\t动物|有袋类动物|树袋熊|澳大利亚\tkoala\tanimal|australia|bear|down|face|marsupial|under\t
    🐼\t3\t0\t熊猫\t头|熊猫脸|猫熊|猫熊脸|胖达|脸\tpanda\tanimal|bamboo|face\t
    🦥\t3\t0\t树懒\t慢|懒|爬树|迟缓\tsloth\tlazy|slow\t
    🦦\t3\t0\t水獭\t动物|好玩|捕鱼|爱开玩笑|獭|鼬\totter\tanimal|fishing|playful\t
    🦨\t3\t0\t臭鼬\t熏|臭|鼬\tskunk\tanimal|stink\t
    🦘\t3\t0\t袋鼠\t动物|小袋鼠|有袋目动物|有袋类动物|澳洲|跳|跳跃\tkangaroo\tanimal|joey|jump|marsupial\t
    🦡\t3\t0\t獾\t动物|打扰|纠缠|蜜獾\tbadger\tanimal|honey|pester\t
    🐾\t3\t0\t爪印\t爪|爪子|足迹\tpaw prints\tfeet|paw|paws|print|prints\t
    🦃\t3\t0\t火鸡\t感恩节\tturkey\tbird|gobble|thanksgiving\t
    🐔\t3\t0\t鸡\t动物\tchicken\tanimal|bird|ornithology\t
    🐓\t3\t0\t公鸡\t动物|鸡\trooster\tanimal|bird|ornithology\t
    🐣\t3\t0\t小鸡破壳\t小鸡|破壳\thatching chick\tanimal|baby|bird|chick|egg|hatching\t
    🐤\t3\t0\t小鸡\t鸡\tbaby chick\tanimal|baby|bird|chick|ornithology\t
    🐥\t3\t0\t正面朝向的小鸡\t小鸡\tfront-facing baby chick\tanimal|baby|bird|chick|front-facing|newborn|ornithology\t
    🐦️\t3\t0\t鸟\t动物|鸟类学\tbird\tanimal|ornithology\t
    🐧\t3\t0\t企鹅\t南极|南极洲\tpenguin\tanimal|antarctica|bird|ornithology\t
    🕊️\t3\t0\t鸽\t和平|和平象征|飞翔|鸟|鸽子\tdove\tbird|fly|ornithology|peace\t
    🦅\t3\t0\t鹰\t老鹰|鸟\teagle\tanimal|bird|ornithology\t
    🦆\t3\t0\t鸭子\t鸟|鸭\tduck\tanimal|bird|ornithology\t
    🦢\t3\t0\t天鹅\t丑小鸭|动物|小天鹅|鸟\tswan\tanimal|bird|cygnet|duckling|ornithology|ugly\t
    🦉\t3\t0\t猫头鹰\t睿智|鸟\towl\tanimal|bird|ornithology|wise\t
    🦤\t3\t0\t渡渡鸟\t动物|灭绝|鸟\tdodo\tanimal|bird|extinction|large|ornithology\t
    🪶\t3\t0\t羽毛\t轻|飞|鸟\tfeather\tbird|flight|light|plumage\t
    🦩\t3\t0\t火烈鸟\t华丽|热带|红鹳|艳丽\tflamingo\tanimal|bird|flamboyant|ornithology|tropical\t
    🦚\t3\t0\t孔雀\t卖弄|招摇|色彩缤纷|雌孔雀|骄傲|鸟\tpeacock\tanimal|bird|colorful|ornithology|ostentatious|peahen|pretty|proud\t
    🦜\t3\t0\t鹦鹉\t剽窃|模仿|说话|鸟\tparrot\tanimal|bird|ornithology|pirate|talk\t
    🪽\t3\t0\t翅膀\t升天|天使|天使的|天堂的|神话|翱翔|飞翔|飞行|鸟\twing\tangelic|ascend|aviation|bird|fly|flying|heavenly|mythology|soar\t
    🐦‍⬛\t3\t0\t黑色的鸟\t乌鸦|动物|喙|渡鸦|秃鼻乌鸦|老鸦|鸟|鸦叫声|鸦科|黑色\tblack bird\tanimal|beak|bird|black|caw|corvid|crow|ornithology|raven|rook\t
    🪿\t3\t0\t鹅\t傻|傻瓜|动物|嘎嘎叫声|家禽|雄鹅|鸟|鸣叫|鸭子|鸭群|鹅群\tgoose\tanimal|bird|duck|flock|fowl|gaggle|gander|geese|honk|ornithology|silly\t
    🐦‍🔥\t3\t0\t凤凰\t不朽|不死鸟|东山再起|凤凰传奇|幻兽|幻想|浴火重生|火鸟|灵魂转世|神奇动物|重生|重获新生\tphoenix\tascend|ascension|emerge|fantasy|firebird|glory|immortal|rebirth|reincarnation|reinvent|renewal|revival|revive|rise|transform\t
    🐸\t3\t0\t青蛙\t动物|头|脸|青蛙头\tfrog\tanimal|face\t
    🐊\t3\t0\t鳄鱼\t鳄鱼\tcrocodile\tanimal|zoo\t
    🐢\t3\t0\t龟\t乌龟|海龟|陆龟\tturtle\tanimal|terrapin|tortoise\t
    🦎\t3\t0\t蜥蜴\t爬行动物\tlizard\tanimal|reptile\t
    🐍\t3\t0\t蛇\t持票人|狡猾的人|蛇夫座|黄道十二宫\tsnake\tanimal|bearer|ophiuchus|serpent|zodiac\t
    🐲\t3\t0\t龙头\t神话|童话|龙\tdragon face\tanimal|dragon|face|fairy|fairytale|tale\t
    🐉\t3\t0\t龙\t中国|权力的游戏\tdragon\tanimal|fairy|fairytale|knights|tale\t
    🦕\t3\t0\t蜥蜴类\t万龙属|恐龙|梁龙|腕龙|雷龙\tsauropod\tbrachiosaurus|brontosaurus|dinosaur|diplodocus\t
    🦖\t3\t0\t霸王龙\t恐龙|暴龙|暴龙君主\tT-Rex\tdinosaur|rex|t|t-rex|tyrannosaurus\t
    🐳\t3\t0\t喷水的鲸\t喷水|鲸\tspouting whale\tanimal|beach|face|ocean|spouting|whale\t
    🐋\t3\t0\t鲸鱼\t鲸鱼\twhale\tanimal|beach|ocean\t
    🐬\t3\t0\t海豚\t鸭脚板\tdolphin\tanimal|beach|flipper|ocean\t
    🦭\t3\t0\t海豹\t动物|海洋|海狮\tseal\tanimal|lion|ocean|sea\t
    🐟️\t3\t0\t鱼\t双鱼座|星座|黄道十二宫\tfish\tanimal|dinner|fishes|fishing|pisces|zodiac\t
    🐠\t3\t0\t热带鱼\t热带|鱼\ttropical fish\tanimal|fish|fishes|tropical\t
    🐡\t3\t0\t河豚\t鱼\tblowfish\tanimal|fish\t
    🦈\t3\t0\t鲨鱼\t鱼|鲨\tshark\tanimal|fish\t
    🐙\t3\t0\t章鱼\t八爪|鱼\toctopus\tanimal|creature|ocean\t
    🐚\t3\t0\t海螺\t螺|螺旋\tspiral shell\tanimal|beach|conch|sea|shell|spiral\t
    🪸\t3\t0\t珊瑚\t气候变化|海洋|珊瑚礁|礁\tcoral\tchange|climate|ocean|reef|sea\t
    🪼\t3\t0\t水母\t刺毛|动物|发光|哎哟|无脊椎动物|有刺动物|果冻|水族馆|浮游生物|海洋|海洋生物|海蜇|触手\tjellyfish\tanimal|aquarium|burn|invertebrate|jelly|life|marine|ocean|ouch|plankton|sea|sting|stinger|tentacles\t
    🦀\t3\t0\t蟹\t巨蟹座|螃蟹|黄道十二宫\tcrab\tcancer|zodiac\t
    🦞\t3\t0\t龙虾\t浓汤|海鲜|红龙虾|贝类浓汤|钳|鳌\tlobster\tanimal|bisque|claws|seafood\t
    🦐\t3\t0\t虾\t甲壳|贝类水产|食物\tshrimp\tfood|shellfish|small\t
    🦑\t3\t0\t乌贼\t墨鱼|软体动物|食物|鱿鱼\tsquid\tanimal|food|mollusk\t
    🦪\t3\t0\t牡蛎\t海鲜|珍珠|生蚝\toyster\tdiving|pearl\t
    🐌\t3\t0\t蜗牛\t法国蜗牛\tsnail\tanimal|escargot|garden|nature|slug\t
    🦋\t3\t0\t蝴蝶\t昆虫|漂亮|美丽\tbutterfly\tinsect|pretty\t
    🐛\t3\t0\t毛毛虫\t昆虫|毛虫\tbug\tanimal|garden|insect\t
    🐜\t3\t0\t蚂蚁\t蚂蚁\tant\tanimal|garden|insect\t
    🐝\t3\t0\t蜜蜂\t勤劳|昆虫|蜂蜜\thoneybee\tanimal|bee|bumblebee|honey|insect|nature|spring\t
    🪲\t3\t0\t甲虫\t动物|昆虫|虫子\tbeetle\tanimal|bug|insect\t
    🐞\t3\t0\t瓢虫\t昆虫|母\tlady beetle\tanimal|beetle|garden|insect|lady|ladybird|ladybug|nature\t
    🦗\t3\t0\t蟋蟀\t昆虫|蚱蜢|蛐蛐\tcricket\tanimal|bug|grasshopper|insect|orthoptera\t
    🪳\t3\t0\t蟑螂\t动物|害虫|小强|昆虫|虫子\tcockroach\tanimal|insect|pest|roach\t
    🕷️\t3\t0\t蜘蛛\t昆虫\tspider\tanimal|insect\t
    🕸️\t3\t0\t蜘蛛网\t蛛网|蜘蛛\tspider web\tspider|web\t
    🦂\t3\t0\t蝎子\t天蝎宫|天蝎座|黄道十二宫\tscorpion\tscorpio|scorpius|zodiac\t
    🦟\t3\t0\t蚊子\t发烧|发热|昆虫|疟疾|疾病|病|病毒\tmosquito\tbite|disease|fever|insect|malaria|pest|virus\t
    🪰\t3\t0\t苍蝇\t动物|害虫|疾病|腐烂|虫子|蛆\tfly\tanimal|disease|insect|maggot|pest|rotting\t
    🪱\t3\t0\t蠕虫\t动物|寄生虫|环节动物|蚯蚓\tworm\tanimal|annelid|earthworm|parasite\t
    🦠\t3\t0\t细菌\t变形虫|病毒|科学|阿米巴\tmicrobe\tamoeba|bacteria|science|virus\t
    💐\t3\t0\t花束\t周年纪念|生日|罗曼史|鲜花\tbouquet\tanniversary|birthday|date|flower|love|plant|romance\t
    🌸\t3\t0\t樱花\t花\tcherry blossom\tblossom|cherry|flower|plant|spring|springtime\t
    💮\t3\t0\t白花\t花\twhite flower\tflower|white\t
    🪷\t3\t0\t莲花\t佛教|印度教|幽静|恬静|纯洁|花|花朵\tlotus\tbeauty|buddhism|calm|flower|hinduism|peace|purity|serenity\t
    🏵️\t3\t0\t圆形花饰\t光荣花|植物|花|花圈\trosette\tplant\t
    🌹\t3\t0\t玫瑰\t优雅|红玫瑰|花\trose\tbeauty|elegant|flower|love|plant|red|valentine\t
    🥀\t3\t0\t枯萎的花\t凋谢|枯萎|花\twilted flower\tdying|flower|wilted\t
    🌺\t3\t0\t芙蓉\t木槿|植物|花\thibiscus\tflower|plant\t
    🌻\t3\t0\t向日葵\t太阳|太阳花|花\tsunflower\tflower|outdoors|plant|sun\t
    🌼\t3\t0\t开花\t花|蒲公英\tblossom\tbuttercup|dandelion|flower|plant\t
    🌷\t3\t0\t郁金香\t开花|花\ttulip\tblossom|flower|growth|plant\t
    🪻\t3\t0\t风信子\t春天|植物|灌木|矢车菊|紫丁香|紫罗兰|紫色|羽扇豆|花|花朵|蓝帽花|薰衣草|金鱼草|靛蓝\thyacinth\tbloom|bluebonnet|flower|indigo|lavender|lilac|lupine|plant|purple|shrub|snapdragon|spring|violet\t
    🌱\t3\t0\t幼苗\t发芽|芽|苗\tseedling\tplant|sapling|sprout|young\t
    🪴\t3\t0\t盆栽植物\t培育|房子|枯燥|植物|生长|盆景|盆栽|花盆\tpotted plant\tdecor|grow|house|nurturing|plant|pot|potted\t
    🌲\t3\t0\t松树\t圣诞树|常青树|树\tevergreen tree\tchristmas|evergreen|forest|pine|tree\t
    🌳\t3\t0\t落叶树\t树|落叶|落叶植物\tdeciduous tree\tdeciduous|forest|green|habitat|shedding|tree\t
    🌴\t3\t0\t棕榈树\t树|棕榈|热带\tpalm tree\tbeach|palm|plant|tree|tropical\t
    🌵\t3\t0\t仙人掌\t干旱|植物|沙漠\tcactus\tdesert|drought|nature|plant\t
    🌾\t3\t0\t稻子\t稻|米|粮食|谷物\tsheaf of rice\tear|grain|grains|plant|rice|sheaf\t
    🌿\t3\t0\t药草\t草药|香草\therb\tleaf|plant\t
    ☘️\t3\t0\t三叶草\t爱尔兰|苜蓿|酢浆草\tshamrock\tirish|plant\t
    🍀\t3\t0\t四叶草\t幸运|爱尔兰的\tfour leaf clover\t4|clover|four|four-leaf|irish|leaf|lucky|plant\t
    🍁\t3\t0\t枫叶\t树叶|秋叶|落叶\tmaple leaf\tfalling|leaf|maple\t
    🍂\t3\t0\t落叶\t叶|秋\tfallen leaf\tautumn|fall|fallen|falling|leaf\t
    🍃\t3\t0\t风吹叶落\t叶子|树叶|随风飘舞\tleaf fluttering in wind\tblow|flutter|fluttering|leaf|wind\t
    🪹\t3\t0\t空巢\t家|树枝|筑巢|鸟巢\tempty nest\tbranch|empty|home|nest|nesting\t
    🪺\t3\t0\t有蛋的巢\t树枝|筑巢|蛋|鸟|鸟巢|鸟蛋\tnest with eggs\tbird|branch|egg|eggs|nest|nesting\t
    🍄\t3\t0\t蘑菇\t毒蕈|真菌\tmushroom\tfungus|toadstool\t
    🪾\t3\t1\t无叶树\t冬天|冬季|干旱|无叶|木|树|树干|树枝|死|秃|荒芜\tleafless tree\tbare|barren|branches|dead|drought|leafless|tree|trunk|winter|wood\t
    🍇\t4\t0\t葡萄\t水果\tgrapes\tdionysus|fruit|grape\t
    🍈\t4\t0\t甜瓜\t哈密瓜|水果|蜜瓜|香瓜\tmelon\tcantaloupe|fruit\t
    🍉\t4\t0\t西瓜\t水果\twatermelon\tfruit\t
    🍊\t4\t0\t橘子\t柑桔|柑橘|桔子|水果|油桃|维他命 c\ttangerine\tc|citrus|fruit|nectarine|orange|vitamin\t
    🍋\t4\t0\t柠檬\t柑橘|水果|酸\tlemon\tcitrus|fruit|sour\t
    🍋‍🟩\t4\t0\t青柠\t柑橘属|橘属|水果|清爽|热带|绿色|莫吉托|调味汁|酸味酒精饮料|酸橙|酸橙派|酸爽\tlime\tacidity|citrus|cocktail|fruit|garnish|key|margarita|mojito|refreshing|salsa|sour|tangy|tequila|tropical|zest\t
    🍌\t4\t0\t香蕉\t水果|钾\tbanana\tfruit|potassium\t
    🍍\t4\t0\t菠萝\t水果|热带\tpineapple\tcolada|fruit|pina|tropical\t
    🥭\t4\t0\t芒果\t水果|热带|食物\tmango\tfood|fruit|tropical\t
    🍎\t4\t0\t红苹果\t健康|水果|熟|红|苹果|食物\tred apple\tapple|diet|food|fruit|health|red|ripe\t
    🍏\t4\t0\t青苹果\t水果|苹果|青\tgreen apple\tapple|fruit|green\t
    🍐\t4\t0\t梨\t水果\tpear\tfruit\t
    🍑\t4\t0\t桃\t水果\tpeach\tfruit\t
    🍒\t4\t0\t樱桃\t水果\tcherries\tberries|cherry|fruit|red\t
    🍓\t4\t0\t草莓\t水果|浆果\tstrawberry\tberry|fruit\t
    🫐\t4\t0\t蓝莓\t水果|浆果|越桔|食物\tblueberries\tberries|berry|bilberry|blue|blueberry|food|fruit\t
    🥝\t4\t0\t猕猴桃\t奇异果|水果|食物\tkiwi fruit\tfood|fruit|kiwi\t
    🍅\t4\t0\t西红柿\t水果|番茄|蔬菜\ttomato\tfood|fruit|vegetable\t
    🫒\t4\t0\t橄榄\t食物\tolive\tfood\t
    🥥\t4\t0\t椰子\t棕榈|菠萝椰子兰姆酒\tcoconut\tcolada|palm|piña\t
    🥑\t4\t0\t鳄梨\t水果|牛油果|酪梨|食物|黄油果\tavocado\tfood|fruit\t
    🍆\t4\t0\t茄子\t蔬菜\teggplant\taubergine|vegetable\t
    🥔\t4\t0\t土豆\t蔬菜|食物|马铃薯\tpotato\tfood|vegetable\t
    🥕\t4\t0\t胡萝卜\t蔬菜|食物\tcarrot\tfood|vegetable\t
    🌽\t4\t0\t玉米\t农作物|包谷|苞米\tear of corn\tcorn|crops|ear|farm|maize|maze\t
    🌶️\t4\t0\t红辣椒\t辣|辣椒\thot pepper\thot|pepper\t
    🫑\t4\t0\t灯笼椒\t蔬菜|辣椒|青椒|食物\tbell pepper\tbell|capsicum|food|pepper|vegetable\t
    🥒\t4\t0\t黄瓜\t泡菜|腌菜|蔬菜|食物\tcucumber\tfood|pickle|vegetable\t
    🥬\t4\t0\t绿叶蔬菜\t卷心菜|圆白菜|小白菜|甘蓝|生菜|羽衣甘蓝|色拉|莴苣\tleafy green\tbok|burgers|cabbage|choy|green|kale|leafy|lettuce|salad\t
    🥦\t4\t0\t西兰花\t甘蓝|野生卷心菜\tbroccoli\tcabbage|wild\t
    🧄\t4\t0\t蒜\t佐料|大蒜|蒜头|调味\tgarlic\tflavoring\t
    🧅\t4\t0\t洋葱\t佐料|调味\tonion\tflavoring\t
    🥜\t4\t0\t花生\t坚果|蔬菜|食物\tpeanuts\tfood|nut|peanut|vegetable\t
    🫘\t4\t0\t豆\t肾|豆子|豆类|食物\tbeans\tfood|kidney|legume|small\t
    🌰\t4\t0\t栗子\t杏仁\tchestnut\talmond|plant\t
    🫚\t4\t0\t姜\t健康|啤酒|天然|根|根汁啤酒|根茎|草药|香料\tginger root\tbeer|ginger|health|herb|natural|root|spice\t
    🫛\t4\t0\t豌豆荚\t大豆|毛豆|素食者|荚|蔬菜|豆|豆类|豆茎|豆荚|豌豆|黄豆\tpea pod\tbeans|beanstalk|edamame|legume|pea|pod|soybean|vegetable|veggie\t
    🍄‍🟫\t4\t0\t褐色蘑菇\t披萨配料|拖沓|无聊|棕色|植物|素食|素食主义者|自然|菌类|蔬菜|蘑菇|褐色|褐菇|食物\tbrown mushroom\tfood|fungi|fungus|mushroom|nature|pizza|portobello|shiitake|shroom|spore|sprout|toppings|truffle|vegetable|vegetarian|veggie\t
    🫜\t4\t1\t根菜\t根|甜菜|素食|色拉|芜菁|菜园|萝卜|蔬菜|食物\troot vegetable\tbeet|food|garden|radish|root|salad|turnip|vegetable|vegetarian\t
    🍞\t4\t0\t面包\t一条面包|全麦面包|小麦|淀粉|烤面包|谷类|食物|餐厅\tbread\tcarbs|food|grain|loaf|restaurant|toast|wheat\t
    🥐\t4\t0\t羊角面包\t新月形面包|法式|牛角面包|面包|食物\tcroissant\tbread|breakfast|crescent|food|french|roll\t
    🥖\t4\t0\t法式长棍面包\t法式|法式长条面包|面包|食物\tbaguette bread\tbaguette|bread|food|french\t
    🫓\t4\t0\t扁面包\t圆盘状烤饼|玉米饼|皮塔饼|薄脆饼|面包|面饼|食物\tflatbread\tarepa|bread|food|gordita|lavash|naan|pita\t
    🥨\t4\t0\t椒盐卷饼\t弯曲|扭曲食品|盘绕|缠绕|错综复杂\tpretzel\tconvoluted|twisted\t
    🥯\t4\t0\t面包圈\t奶酪酱|早餐|烘烤食品|硬面包圈|贝果|面包\tbagel\tbakery|bread|breakfast|schmear\t
    🥞\t4\t0\t烙饼\t煎饼|薄煎饼|薄饼|食物\tpancakes\tbreakfast|crêpe|food|hotcake|pancake\t
    🧇\t4\t0\t华夫饼\t松饼|格子饼|点心|烤|甜点|窝夫饼\twaffle\tbreakfast|indecisive|iron\t
    🧀\t4\t0\t芝士\t奶酪|起司\tcheese wedge\tcheese|wedge\t
    🍖\t4\t0\t排骨\t带骨的肉|肉|骨\tmeat on bone\tbone|meat\t
    🍗\t4\t0\t家禽的腿\t家禽|火鸡|饿|骨|鸡肉|鸡腿\tpoultry leg\tbone|chicken|drumstick|hungry|leg|poultry|turkey\t
    🥩\t4\t0\t肉块\t排骨|牛排|猪排|红肉|羊排|肉|肉排\tcut of meat\tchop|cut|lambchop|meat|porkchop|red|steak\t
    🥓\t4\t0\t培根\t烟肉|熏肉|肉|背肯|食物\tbacon\tbreakfast|food|meat\t
    🍔\t4\t0\t汉堡\t吃|汉堡包|速食|食物|饿\thamburger\tburger|eat|fast|food|hungry\t
    🍟\t4\t0\t薯条\t快餐|油炸|食物\tfrench fries\tfast|food|french|fries\t
    🍕\t4\t0\t披萨\t一片比萨|比萨|比萨饼|起司|辣味香肠|食物|饿\tpizza\tcheese|food|hungry|pepperoni|slice\t
    🌭\t4\t0\t热狗\t香肠\thot dog\tdog|frankfurter|hot|hotdog|sausage\t
    🥪\t4\t0\t三明治\t面包\tsandwich\tbread\t
    🌮\t4\t0\t墨西哥卷饼\t卷饼|墨西哥|墨西哥玉米卷|玉米卷饼\ttaco\tmexican\t
    🌯\t4\t0\t墨西哥玉米煎饼\t卷饼|墨西哥|墨西哥卷饼|玉米煎饼\tburrito\tmexican|wrap\t
    🫔\t4\t0\t墨西哥粽子\t墨西哥|墨西哥饼|巴西粽|粽子|食物\ttamale\tfood|mexican|pamonha|wrapped\t
    🥙\t4\t0\t夹心饼\t大饼|夹心|沙拉三明治|炸豆丸子|烤肉串|肉夹馍|食物\tstuffed flatbread\tfalafel|flatbread|food|gyro|kebab|stuffed\t
    🧆\t4\t0\t炸豆丸子\t中东蔬菜球|油炸鹰嘴豆饼|肉丸|鹰嘴豆\tfalafel\tchickpea|meatball\t
    🥚\t4\t0\t蛋\t食物\tegg\tbreakfast|food\t
    🍳\t4\t0\t煎蛋\t一面老一面嫩的煎蛋|做菜|只煎一面老|平底锅|早餐|煎|蛋|食堂\tcooking\tbreakfast|easy|egg|fry|frying|over|pan|restaurant|side|sunny|up\t
    🥘\t4\t0\t装有食物的浅底锅\t平底锅|浅底|炖菜|炖锅|煎锅|西班牙海鲜饭|食物\tshallow pan of food\tcasserole|food|paella|pan|shallow\t
    🍲\t4\t0\t一锅食物\t炖菜|锅|食物\tpot of food\tfood|pot|soup|stew\t
    🫕\t4\t0\t奶酪火锅\t奶酪|奶酪锅|巧克力|火锅|煮|煲汤|瑞士|融化|锅|食物\tfondue\tcheese|chocolate|food|melted|pot|ski\t
    🥣\t4\t0\t碗勺\t早餐|燕麦|燕麦粥|碗中汤匙|碗和汤匙|稀饭|粥|谷物\tbowl with spoon\tbowl|breakfast|cereal|congee|oatmeal|porridge|spoon\t
    🥗\t4\t0\t绿色沙拉\t沙拉|绿色蔬菜|食物\tgreen salad\tfood|green|salad\t
    🍿\t4\t0\t爆米花\t看电影\tpopcorn\tcorn|movie|pop\t
    🧈\t4\t0\t黄油\t乳制品|牛奶\tbutter\tdairy\t
    🧂\t4\t0\t盐\t佐料瓶|味道|咸|火大|调味品|调味料\tsalt\tcondiment|flavor|mad|salty|shaker|taste|upset\t
    🥫\t4\t0\t罐头食品\t罐头\tcanned food\tcan|canned|food\t
    🍱\t4\t0\t盒饭\t便当|便当盒|食物\tbento box\tbento|box|food\t
    🍘\t4\t0\t米饼\t米|米果|食物\trice cracker\tcracker|food|rice\t
    🍙\t4\t0\t饭团\t日式饭团|日本|米|食物\trice ball\tball|food|japanese|rice\t
    🍚\t4\t0\t米饭\t主食|米|食物|饭\tcooked rice\tcooked|food|rice\t
    🍛\t4\t0\t咖喱饭\t咖喱|食物|饭\tcurry rice\tcurry|food|rice\t
    🍜\t4\t0\t面条\t拉面|河粉|热气腾腾|热气腾腾面碗|碗|筷子|食物\tsteaming bowl\tbowl|chopsticks|food|noodle|pho|ramen|soup|steaming\t
    🍝\t4\t0\t意粉\t意大利面|意面|肉丸|食物|餐厅\tspaghetti\tfood|meatballs|pasta|restaurant\t
    🍠\t4\t0\t烤红薯\t地瓜|烤地瓜|红薯|食物\troasted sweet potato\tfood|potato|roasted|sweet\t
    🍢\t4\t0\t关东煮\t串|卡博|海鲜|食物|餐馆\toden\tfood|kebab|restaurant|seafood|skewer|stick\t
    🍣\t4\t0\t寿司\t食物\tsushi\tfood\t
    🍤\t4\t0\t天妇罗\t对虾|油炸|炸虾|虾\tfried shrimp\tfried|prawn|shrimp|tempura\t
    🍥\t4\t0\t鱼板\t鱼|鱼饼\tfish cake with swirl\tcake|fish|food|pastry|restaurant|swirl\t
    🥮\t4\t0\t月饼\t中秋节|秋|秋天|节日\tmoon cake\tautumn|cake|festival|moon|yuèbǐng\t
    🍡\t4\t0\t团子\t串|和果子|日本|甜点|糖葫芦\tdango\tdessert|japanese|skewer|stick|sweet\t
    🥟\t4\t0\t饺子\t恩潘纳达|水饺|波兰饺子|煎饺\tdumpling\tempanada|gyōza|jiaozi|pierogi|potsticker\t
    🥠\t4\t0\t幸运饼干\t签餅|算命|预言\tfortune cookie\tcookie|fortune|prophecy\t
    🥡\t4\t0\t外卖盒\t中式外卖|外卖|外卖包装|外卖桶|外卖餐盒|牡蛎桶|盒饭|筷子|送餐|送餐服务\ttakeout box\tbox|chopsticks|delivery|food|oyster|pail|takeout\t
    🍦\t4\t0\t圆筒冰激凌\t冰淇淋|圆筒冰淇淋|甜|甜点|霜淇淋|食物\tsoft ice cream\tcream|dessert|food|ice|icecream|restaurant|serve|soft|sweet\t
    🍧\t4\t0\t刨冰\t冰|冰沙|沙冰|甜|甜点|餐馆\tshaved ice\tdessert|ice|restaurant|shaved|sweet\t
    🍨\t4\t0\t冰淇淋\t冰|冰激凌|奶油|甜|甜点|雪糕\tice cream\tcream|dessert|food|ice|restaurant|sweet\t
    🍩\t4\t0\t甜甜圈\t甜|甜点|食物\tdoughnut\tbreakfast|dessert|donut|food|sweet\t
    🍪\t4\t0\t饼干\t巧克力片|曲奇|曲奇饼|甜点\tcookie\tchip|chocolate|dessert|sweet\t
    🎂\t4\t0\t生日蛋糕\t庆祝|甜|甜点|生日|生日快乐|糕点|蛋糕\tbirthday cake\tbday|birthday|cake|celebration|dessert|happy|pastry|sweet\t
    🍰\t4\t0\t水果蛋糕\t一片蛋糕|奶油|奶油酥饼|甜点|糕点|蛋糕\tshortcake\tcake|dessert|pastry|slice|sweet\t
    🧁\t4\t0\t纸杯蛋糕\t烘焙食品|甜点|请客|面包店\tcupcake\tbakery|dessert|sprinkles|sugar|sweet|treat\t
    🥧\t4\t0\t派\t一片派|南瓜派|水果派|油酥点心|糕点|肉排|苹果派|馅\tpie\tapple|filling|fruit|meat|pastry|pumpkin|slice\t
    🍫\t4\t0\t巧克力\t万圣节|巧克力棒|甜|甜品|甜点|糖果\tchocolate bar\tbar|candy|chocolate|dessert|halloween|sweet|tooth\t
    🍬\t4\t0\t糖\t万圣节|嗜甜食|爱吃甜食|甜|甜点|糖果|糖果纸|蛀牙|餐馆\tcandy\tcavities|dessert|halloween|restaurant|sweet|tooth|wrapper\t
    🍭\t4\t0\t棒棒糖\t果子|甜|糖|糖果\tlollipop\tcandy|dessert|food|restaurant|sweet\t
    🍮\t4\t0\t奶黄\t卡士达|甜点|蛋奶冻|蛋奶沙司\tcustard\tdessert|pudding|sweet\t
    🍯\t4\t0\t蜂蜜\t小熊维尼|桶|甜|蜜罐\thoney pot\tbarrel|bear|food|honey|honeypot|jar|pot|sweet\t
    🍼\t4\t0\t奶瓶\t奶|婴儿|新生儿\tbaby bottle\tbabies|baby|birth|born|bottle|drink|infant|milk|newborn\t
    🥛\t4\t0\t一杯奶\t喝|奶|杯|牛奶\tglass of milk\tdrink|glass|milk\t
    ☕️\t4\t0\t热饮\t咖啡|早晨|星巴克|热气腾腾|茶|饮料\thot beverage\tbeverage|cafe|caffeine|chai|coffee|drink|hot|morning|steaming|tea\t
    🫖\t4\t0\t茶壶\t冲泡|壶|茶|食物\tteapot\tbrew|drink|food|pot|tea\t
    🍵\t4\t0\t热茶\t乌龙茶|无柄茶杯|杯|没有把手的茶杯|热饮|茶|茶杯|饮料\tteacup without handle\tbeverage|cup|drink|handle|oolong|tea|teacup\t
    🍶\t4\t0\t清酒\t喝酒|清酒杯|清酒瓶|瓶|酒|酒吧|酒杯|饮料\tsake\tbar|beverage|bottle|cup|drink|restaurant\t
    🍾\t4\t0\t开香槟\t喝酒|庆祝|木塞|瓶子|砰|砰木塞的瓶子|香槟\tbottle with popping cork\tbar|bottle|cork|drink|popping\t
    🍷\t4\t0\t葡萄酒\t俱乐部|喝酒|酒|酒吧|酒杯|饮料\twine glass\talcohol|bar|beverage|booze|club|drink|drinking|drinks|glass|restaurant|wine\t
    🍸️\t4\t0\t鸡尾酒\t俱乐部|喝酒|杯|玻璃杯|酒|酒吧|马丁尼|鸡尾酒杯\tcocktail glass\talcohol|bar|booze|club|cocktail|drink|drinking|drinks|glass|mad|martini|men\t
    🍹\t4\t0\t热带水果饮料\t俱乐部|喝酒|热带饮料|酒|酒吧|饮料|鸡尾酒\ttropical drink\talcohol|bar|booze|club|cocktail|drink|drinking|drinks|drunk|mai|party|tai|tropical|tropics\t
    🍺\t4\t0\t啤酒\t啤酒节|喝酒|杯|酒|酒吧\tbeer mug\talcohol|ale|bar|beer|booze|drink|drinking|drinks|mug|octoberfest|oktoberfest|pint|stein|summer\t
    🍻\t4\t0\t干杯\t啤酒|喝酒|碰杯|酒|酒吧\tclinking beer mugs\talcohol|bar|beer|booze|bottoms|cheers|clink|clinking|drinking|drinks|mugs\t
    🥂\t4\t0\t碰杯\t喝|干杯|庆祝|杯\tclinking glasses\tcelebrate|clink|clinking|drink|glass|glasses\t
    🥃\t4\t0\t平底杯\t一杯威士忌|威士忌|平底无脚杯|杯|玻璃杯|酒|随行杯\ttumbler glass\tglass|liquor|scotch|shot|tumbler|whiskey|whisky\t
    🫗\t4\t0\t倾倒液体\t倒出|倾倒|洒出|流出|玻璃杯|碰倒|空|饮料\tpouring liquid\taccident|drink|empty|glass|liquid|oops|pour|pouring|spill|water\t
    🥤\t4\t0\t带吸管杯\t带吸管的杯子|果汁|水|汽水|苏打|苏打饮料|软饮料|麦乳精饮料\tcup with straw\tcup|drink|juice|malt|soda|soft|straw|water\t
    🧋\t4\t0\t珍珠奶茶\t奶茶|泡泡|牛奶|珍珠|茶|茶饮|饮料\tbubble tea\tboba|bubble|food|milk|pearl|tea\t
    🧃\t4\t0\t饮料盒\t吸管|果汁|果汁盒|甜味|盒装\tbeverage box\tbeverage|box|juice|straw|sweet\t
    🧉\t4\t0\t马黛茶\t茶|饮料\tmate\tdrink\t
    🧊\t4\t0\t冰块\t冰|冰冷|冰山|冷|冷却|冷饮\tice\tcold|cube|iceberg\t
    🥢\t4\t0\t筷子\t箸\tchopsticks\thashi|jeotgarak|kuaizi\t
    🍽️\t4\t0\t餐具\t做菜|刀|刀叉与盘|叉|晚餐|烹饪|盘|西餐\tfork and knife with plate\tcooking|dinner|eat|fork|knife|plate\t
    🍴\t4\t0\t刀叉\t中餐|刀|午餐|叉|吃|吃早餐|吃饭|好吃|早餐|晚餐|烹调|西餐|餐具|饿了\tfork and knife\tbreakfast|breaky|cooking|cutlery|delicious|dinner|eat|feed|food|fork|hungry|knife|lunch|restaurant|yum|yummy\t
    🥄\t4\t0\t匙\t勺|勺子|匙子|汤匙|调羹|餐具\tspoon\teat|tableware\t
    🔪\t4\t0\t菜刀\t主厨|刀|武器|烹饪\tkitchen knife\tchef|cooking|hocho|kitchen|knife|tool|weapon\t
    🫙\t4\t0\t罐\t容器|瓶子|空|空瓶|调味品|贮藏|酱\tjar\tcondiment|container|empty|nothing|sauce|store\t
    🏺\t4\t0\t双耳瓶\t壶|水瓶|罐\tamphora\taquarius|cooking|drink|jug|tool|weapon|zodiac\t
    🌍️\t5\t0\t地球上的欧洲非洲\t世界|地球|欧洲|非洲\tglobe showing Europe-Africa\tafrica|earth|europe|europe-africa|globe|showing|world\t
    🌎️\t5\t0\t地球上的美洲\t世界|全球|地球|美洲\tglobe showing Americas\tamericas|earth|globe|showing|world\t
    🌏️\t5\t0\t地球上的亚洲澳洲\t世界|亚洲|亚澳|全球|地球|地球上的亚洲|澳洲\tglobe showing Asia-Australia\tasia|asia-australia|australia|earth|globe|showing|world\t
    🌐\t5\t0\t带经纬线的地球\t世界|全球|地球|子午线|经纬|经线\tglobe with meridians\tearth|globe|internet|meridians|web|world|worldwide\t
    🗺️\t5\t0\t世界地图\t世界|地图\tworld map\tmap|world\t
    🗾\t5\t0\t日本地图\t地图|日本\tmap of Japan\tjapan|map\t
    🧭\t5\t0\t指南针\t定向|导航|方向|磁性|罗盘\tcompass\tdirection|magnetic|navigation|orienteering\t
    🏔️\t5\t0\t雪山\t冷|山|泠|雪|雪封山头|雪顶\tsnow-capped mountain\tcold|mountain|snow|snow-capped\t
    ⛰️\t5\t0\t山\t峰\tmountain\tmountain\t
    🌋\t5\t0\t火山\t喷发|大自然|山|爆发\tvolcano\teruption|mountain|nature\t
    🗻\t5\t0\t富士山\t大自然|山\tmount fuji\tfuji|mount|mountain|nature\t
    🏕️\t5\t0\t露营\t帐篷\tcamping\tcamping\t
    🏖️\t5\t0\t沙滩伞\t伞|有伞的海滩|沙滩|海滩|阳伞\tbeach with umbrella\tbeach|umbrella\t
    🏜️\t5\t0\t沙漠\t荒漠\tdesert\tdesert\t
    🏝️\t5\t0\t无人荒岛\t岛|沙滩孤岛|沙漠|荒岛\tdesert island\tdesert|island\t
    🏞️\t5\t0\t国家公园\t公园|自然|风景\tnational park\tnational|park\t
    🏟️\t5\t0\t体育馆\t竞技场\tstadium\tstadium\t
    🏛️\t5\t0\t古典建筑\t古典|古建筑\tclassical building\tbuilding|classical\t
    🏗️\t5\t0\t施工\t兴建|建筑施工\tbuilding construction\tbuilding|construction|crane\t
    🧱\t5\t0\t砖\t墙|砂浆|黏土\tbrick\tbricks|clay|mortar|wall\t
    🪨\t5\t0\t岩石\t固体|坚不可摧|巨石|石头\trock\tboulder|heavy|solid|stone|tough\t
    🪵\t5\t0\t木头\t原木|圆木|木材|木桩\twood\tlog|lumber|timber\t
    🛖\t5\t0\t小屋\t圆屋|家|茅屋|蒙古包\thut\thome|house|roundhouse|shelter|yurt\t
    🏘️\t5\t0\t房屋建筑\t住宅|小区|房|房子\thouses\thouse\t
    🏚️\t5\t0\t废墟\t废屋|荒宅|荒废|鬼屋\tderelict house\tderelict|home|house\t
    🏠️\t5\t0\t房子\t乡村家园|住家|家|建筑|心之所在|房屋|郊区\thouse\tbuilding|country|heart|home|ranch|settle|simple|suburban|suburbia|where\t
    🏡\t5\t0\t别墅\t乡村家园|住家|家|庭院|庭院居家|建筑|心之所在|房子|花园|郊区\thouse with garden\tbuilding|country|garden|heart|home|house|ranch|settle|simple|suburban|suburbia|where\t
    🏢\t5\t0\t办公楼\t写字楼|建筑\toffice building\tbuilding|city|cubical|job|office\t
    🏣\t5\t0\t日本邮局\t建筑|日本|邮便|邮局\tJapanese post office\tbuilding|japanese|office|post\t
    🏤\t5\t0\t邮局\t建筑|欧洲|欧洲邮局\tpost office\tbuilding|european|office|post\t
    🏥\t5\t0\t医院\t医生|医药|建筑|看病\thospital\tbuilding|doctor|medicine\t
    🏦\t5\t0\t银行\t建筑\tbank\tbuilding\t
    🏨\t5\t0\t酒店\t建筑|旅馆\thotel\tbuilding\t
    🏩\t5\t0\t情人酒店\t建筑|情人旅馆|情侣酒店|旅馆\tlove hotel\tbuilding|hotel|love\t
    🏪\t5\t0\t便利店\t24 小时|商店|建筑\tconvenience store\t24|building|convenience|hours|store\t
    🏫\t5\t0\t学校\t建筑|教学楼\tschool\tbuilding\t
    🏬\t5\t0\t商场\t建筑|百货公司|百货商城|百货商店\tdepartment store\tbuilding|department|store\t
    🏭️\t5\t0\t工厂\t建筑\tfactory\tbuilding\t
    🏯\t5\t0\t日本城堡\t城堡|建筑|日本\tJapanese castle\tbuilding|castle|japanese\t
    🏰\t5\t0\t欧洲城堡\t城堡|建筑|欧洲\tcastle\tbuilding|european\t
    💒\t5\t0\t婚礼\t教堂|浪漫|结婚\twedding\tchapel|hitched|nuptials|romance\t
    🗼\t5\t0\t东京塔\t东京|塔\tTokyo tower\ttokyo|tower\t
    🗽\t5\t0\t自由女神像\t塑像|纽约|自由|雕塑\tStatue of Liberty\tliberty|new|ny|nyc|statue|york\t
    ⛪️\t5\t0\t教堂\t基督|基督教|宗教|小教堂\tchurch\tbless|chapel|christian|cross|religion\t
    🕌\t5\t0\t清真寺\t伊斯兰|宗教|穆斯林\tmosque\tislam|masjid|muslim|religion\t
    🛕\t5\t0\t印度寺庙\t佛寺|佛教|寺庙|寺院|庙宇\thindu temple\thindu|temple\t
    🕍\t5\t0\t犹太教堂\t会堂|宗教|犹太|犹太教\tsynagogue\tjew|jewish|judaism|religion|temple\t
    ⛩️\t5\t0\t神社\t宗教|日本|神道教\tshinto shrine\treligion|shinto|shrine\t
    🕋\t5\t0\t克尔白\t伊斯兰|天房|宗教|穆斯林\tkaaba\thajj|islam|muslim|religion|umrah\t
    ⛲️\t5\t0\t喷泉\t喷泉\tfountain\tfountain\t
    ⛺️\t5\t0\t帐篷\t露营\ttent\tcamping\t
    🌁\t5\t0\t有雾\t雾|霾\tfoggy\tfog\t
    🌃\t5\t0\t夜晚\t星空|晚上\tnight with stars\tnight|star|stars\t
    🏙️\t5\t0\t城市风光\t城市|都市|都市景观|高楼大厦\tcityscape\tcity\t
    🌄\t5\t0\t山顶日出\t太阳|山|日出|早晨|清晨\tsunrise over mountains\tmorning|mountains|over|sun|sunrise\t
    🌅\t5\t0\t日出\t大自然|太阳|早晨|清晨\tsunrise\tmorning|nature|sun\t
    🌆\t5\t0\t城市黄昏\t城市|夜晚|日落|都市|黄昏\tcityscape at dusk\tat|building|city|cityscape|dusk|evening|landscape|sun|sunset\t
    🌇\t5\t0\t日落\t夕阳\tsunset\tbuilding|dusk|sun\t
    🌉\t5\t0\t夜幕下的桥\t夜幕|晚上|桥\tbridge at night\tat|bridge|night\t
    ♨️\t5\t0\t温泉\t水|泉|热气腾腾|蒸汽\thot springs\thot|hotsprings|springs|steaming\t
    🎠\t5\t0\t旋转木马\t木马|游乐园\tcarousel horse\tcarousel|entertainment|horse\t
    🛝\t5\t0\t游乐场滑梯\t游乐园|游乐场|滑梯|玩|玩耍\tplayground slide\tamusement|park|play|playground|playing|slide|sliding|theme\t
    🎡\t5\t0\t摩天轮\t游乐园\tferris wheel\tamusement|ferris|park|theme|wheel\t
    🎢\t5\t0\t过山车\t游乐园\troller coaster\tamusement|coaster|park|roller|theme\t
    💈\t5\t0\t理发店\t旋转|柱|理发|理发师|理发店旋转彩柱\tbarber pole\tbarber|cut|fresh|haircut|pole|shave\t
    🎪\t5\t0\t马戏团帐篷\t帐篷|马戏团\tcircus tent\tcircus|tent\t
    🚂\t5\t0\t蒸汽火车\t守车|旅行|火车|火车头|蒸汽|蒸汽车头|铁路\tlocomotive\tcaboose|engine|railway|steam|train|trains|travel\t
    🚃\t5\t0\t轨道车\t旅行|电车|铁路\trailway car\tcar|electric|railway|train|tram|travel|trolleybus\t
    🚄\t5\t0\t高速列车\t动车|新干线|火车|速度|高铁\thigh-speed train\thigh-speed|railway|shinkansen|speed|train\t
    🚅\t5\t0\t子弹头高速列车\t动车|子弹列车|子弹头|新干线|火车|高速|高铁\tbullet train\tbullet|high-speed|nose|railway|shinkansen|speed|train|travel\t
    🚆\t5\t0\t火车\t到站|呜呜|铁路\ttrain\tarrived|choo|railway\t
    🚇️\t5\t0\t地铁\t捷运\tmetro\tsubway|travel\t
    🚈\t5\t0\t轻轨\t到站|单轨电车|火车\tlight rail\tarrived|light|monorail|rail|railway\t
    🚉\t5\t0\t车站\t地铁|捷运|火车|铁路\tstation\trailway|train\t
    🚊\t5\t0\t路面电车\t捷运|电车\ttram\ttrolleybus\t
    🚝\t5\t0\t单轨\t单轨电车|火车\tmonorail\tvehicle\t
    🚞\t5\t0\t山区铁路\t山区|山地铁路|火车|铁路\tmountain railway\tcar|mountain|railway|trip\t
    🚋\t5\t0\t有轨电车\t轨道\ttram car\tbus|car|tram|trolley|trolleybus\t
    🚌\t5\t0\t公交车\t公交|公共汽车|大巴\tbus\tschool|vehicle\t
    🚍️\t5\t0\t迎面驶来的公交车\t公交|公共汽车|大巴|迎面驶来\toncoming bus\tbus|cars|oncoming\t
    🚎\t5\t0\t无轨电车\t公共汽车|电车\ttrolleybus\tbus|tram|trolley\t
    🚐\t5\t0\t小巴\t公共汽车|开车|移动房车\tminibus\tbus|drive|van|vehicle\t
    🚑️\t5\t0\t救护车\t急救|车辆\tambulance\temergency|vehicle\t
    🚒\t5\t0\t消防车\t救火车|火灾\tfire engine\tengine|fire|truck\t
    🚓\t5\t0\t警车\t巡逻|檀岛警騎|汽车|警察\tpolice car\t5–0|car|cops|patrol|police\t
    🚔️\t5\t0\t迎面驶来的警车\t汽车|警察|警车\toncoming police car\tcar|oncoming|police\t
    🚕\t5\t0\t出租车\t小黄|开车|汽车|的士|计程车\ttaxi\tcab|cabbie|car|drive|vehicle|yellow\t
    🚖\t5\t0\t迎面驶来的出租车\t优步|出租车|叫车|小黄|开车|的士\toncoming taxi\tcab|cabbie|cars|drove|hail|oncoming|taxi|yellow\t
    🚗\t5\t0\t汽车\t开车|轿车\tautomobile\tcar|driving|vehicle\t
    🚘️\t5\t0\t迎面驶来的汽车\t开车|汽车|轿车|迎面而来\toncoming automobile\tautomobile|car|cars|drove|oncoming|vehicle\t
    🚙\t5\t0\t运动型多用途车\tsuv|休旅车|休闲车|开车|房车|汽车|车辆|轿车|驾驶\tsport utility vehicle\tcar|drive|recreational|sport|sportutility|utility|vehicle\t
    🛻\t5\t0\t敞蓬小型载货卡车\t交通工具|卡车|汽车|皮卡|车|载货\tpickup truck\tautomobile|car|flatbed|pick-up|pickup|transportation|truck\t
    🚚\t5\t0\t货车\t卡车|开车|送货\tdelivery truck\tcar|delivery|drive|truck|vehicle\t
    🚛\t5\t0\t铰接式货车\t卡车|拖车|搬运|货车|铰接式卡车\tarticulated lorry\tarticulated|car|drive|lorry|move|semi|truck|vehicle\t
    🚜\t5\t0\t拖拉机\t拖拉机\ttractor\tvehicle\t
    🏎️\t5\t0\t赛车\t汽车|疾驰|跑车\tracing car\tcar|racing|zoom\t
    🏍️\t5\t0\t摩托车\t摩托|赛车\tmotorcycle\tracing\t
    🛵\t5\t0\t小型摩托车\t摩托车|踏板车\tmotor scooter\tmotor|scooter\t
    🦽\t5\t0\t手动轮椅\t无障碍|轮椅\tmanual wheelchair\taccessibility|manual|wheelchair\t
    🦼\t5\t0\t电动轮椅\t无障碍|轮椅\tmotorized wheelchair\taccessibility|motorized|wheelchair\t
    🛺\t5\t0\t三轮摩托车\t三脚鸡|三蹦子|嘟嘟车|电动三轮车|自动人力车|黄包车\tauto rickshaw\tauto|rickshaw|tuk\t
    🚲️\t5\t0\t自行车\t单车|脚踏车|自行车骑士|飞驰|骑车|骑车疾驰\tbicycle\tbike|class|cycle|cycling|cyclist|gang|ride|spin|spinning\t
    🛴\t5\t0\t滑板车\t滑板车\tkick scooter\tkick|scooter\t
    🛹\t5\t0\t滑板\t板|踩滑板\tskateboard\tboard|skate|skater|wheels\t
    🛼\t5\t0\t四轮滑冰鞋\t旱冰|溜冰|溜冰鞋|滑冰|轮式|运动\troller skate\tblades|roller|skate|skates|sport\t
    🚏\t5\t0\t公交车站\t公交站|公共汽车站\tbus stop\tbus|busstop|stop\t
    🛣️\t5\t0\t高速公路\t公路\tmotorway\thighway|road\t
    🛤️\t5\t0\t铁轨\t火车|铁路\trailway track\trailway|track|train\t
    🛢️\t5\t0\t石油桶\t桶|油桶|石油\toil drum\tdrum|oil\t
    ⛽️\t5\t0\t油泵\t加油|加油站|柴油|燃料|燃油\tfuel pump\tdiesel|fuel|fuelpump|gas|gasoline|pump|station\t
    🛞\t5\t0\t车轮\t圆圈|汽车|车辆|转动|轮胎\twheel\tcar|circle|tire|turn|vehicle\t
    🚨\t5\t0\t警车灯\t灯|紧急|警报|警灯|警示\tpolice car light\talarm|alert|beacon|car|emergency|light|police|revolving|siren\t
    🚥\t5\t0\t横向的红绿灯\t交通灯|信号灯|红绿灯\thorizontal traffic light\thorizontal|intersection|light|signal|stop|stoplight|traffic\t
    🚦\t5\t0\t纵向的红绿灯\t交叉口|交通灯|信号灯|直的红绿灯|红绿灯\tvertical traffic light\tdrove|intersection|light|signal|stop|stoplight|traffic|vertical\t
    🛑\t5\t0\t停止标志\t停止|八角形|八边形|标志\tstop sign\toctagonal|sign|stop\t
    🚧\t5\t0\t路障\t施工\tconstruction\tbarrier\t
    ⚓️\t5\t0\t锚\t停泊|工具|船\tanchor\tship|tool\t
    🛟\t5\t0\t救生圈\t安全|救援|救生|救生用具|游泳|漂浮\tring buoy\tbuoy|float|life|lifesaver|preserver|rescue|ring|safety|save|saver|swim\t
    ⛵️\t5\t0\t帆船\t游艇|船|驾帆船\tsailboat\tboat|resort|sailing|sea|yacht\t
    🛶\t5\t0\t独木舟\t船\tcanoe\tboat\t
    🚤\t5\t0\t快艇\t亿万富翁|船|豪华游艇\tspeedboat\tbillionaire|boat|lake|luxury|millionaire|summer|travel\t
    🛳️\t5\t0\t客轮\t客船|旅客\tpassenger ship\tpassenger|ship\t
    ⛴️\t5\t0\t渡轮\t旅客|渡船|轮船\tferry\tboat|passenger\t
    🛥️\t5\t0\t摩托艇\t船\tmotor boat\tboat|motor|motorboat\t
    🚢\t5\t0\t船\t旅客|旅行\tship\tboat|passenger|travel\t
    ✈️\t5\t0\t飞机\t喷气机|旅行|飞行\tairplane\taeroplane|fly|flying|jet|plane|travel\t
    🛩️\t5\t0\t小型飞机\t小飞机|飞机\tsmall airplane\taeroplane|airplane|plane|small\t
    🛫\t5\t0\t航班起飞\t值机|出境|报到|登机|离境|航班|起飞|飞机\tairplane departure\taeroplane|airplane|check-in|departure|departures|plane\t
    🛬\t5\t0\t航班降落\t到达|着陆|航班|降落|飞机\tairplane arrival\taeroplane|airplane|arrival|arrivals|arriving|landing|plane\t
    🪂\t5\t0\t降落伞\t帆伞|悬挂滑翔|滑翔|滑翔伞|跳伞\tparachute\thang-glide|parasail|skydive\t
    💺\t5\t0\t座位\t位子|椅子\tseat\tchair\t
    🚁\t5\t0\t直升机\t旅行|直升飞机\thelicopter\tcopter|roflcopter|travel|vehicle\t
    🚟\t5\t0\t空轨\t悬挂|悬挂式单轨|空中轨道列车\tsuspension railway\trailway|suspension\t
    🚠\t5\t0\t缆车\t空中|索道\tmountain cableway\tcable|cableway|gondola|lift|mountain|ski\t
    🚡\t5\t0\t索道\t空中|缆车\taerial tramway\taerial|cable|car|gondola|ropeway|tramway\t
    🛰️\t5\t0\t卫星\t太空\tsatellite\tspace\t
    🚀\t5\t0\t火箭\t发射|太空|旅行\trocket\tlaunch|rockets|space|travel\t
    🛸\t5\t0\t飞碟\tufo|不明飞行物|外星人|外星球\tflying saucer\taliens|extra|flying|saucer|terrestrial|ufo\t
    🛎️\t5\t0\t服务铃\t行李员|酒店|铃\tbellhop bell\tbell|bellhop|hotel\t
    🧳\t5\t0\t行李箱\t包装|手提箱|旅行|滚轮提箱|行李\tluggage\tbag|packing|roller|suitcase|travel\t
    ⌛️\t5\t0\t沙漏\t时间|计时|计时器\thourglass done\tdone|hourglass|sand|time|timer\t
    ⏳️\t5\t0\t沙正往下流的沙漏\t沙|沙漏|等待|计时器\thourglass not done\tdone|flowing|hourglass|hours|not|sand|timer|waiting|yolo\t
    ⌚️\t5\t0\t手表\t时间|表\twatch\tclock|time\t
    ⏰️\t5\t0\t闹钟\t小时|时间|钟\talarm clock\talarm|clock|hours|hrs|late|time|waiting\t
    ⏱️\t5\t0\t秒表\t码表|计时|计时器\tstopwatch\tclock|time\t
    ⏲️\t5\t0\t定时器\t时间|计时|计时器\ttimer clock\tclock|timer\t
    🕰️\t5\t0\t座钟\t台钟|壁炉钟|时钟\tmantelpiece clock\tclock|mantelpiece|time\t
    🕛️\t5\t0\t十二点\t00|12|12:00|整点|时间|点钟|钟\ttwelve o’clock\t12|12:00|clock|o’clock|time|twelve\t
    🕧️\t5\t0\t十二点半\t12|12:30|30|时钟\ttwelve-thirty\t12|12:30|30|clock|thirty|time|twelve\t
    🕐️\t5\t0\t一点\t00|1|1:00|时间\tone o’clock\t1|1:00|clock|one|o’clock|time\t
    🕜️\t5\t0\t一点半\t1|1:30|30|时间|钟\tone-thirty\t1|1:30|30|clock|one|thirty|time\t
    🕑️\t5\t0\t两点\t00|2|2:00|时钟\ttwo o’clock\t2|2:00|clock|o’clock|time|two\t
    🕝️\t5\t0\t两点半\t2|2:30|30|时间|钟\ttwo-thirty\t2|2:30|30|clock|thirty|time|two\t
    🕒️\t5\t0\t三点\t00|3|3:00|时钟\tthree o’clock\t3|3:00|clock|o’clock|three|time\t
    🕞️\t5\t0\t三点半\t3|30|3:30|时间|钟\tthree-thirty\t3|30|3:30|clock|thirty|three|time\t
    🕓️\t5\t0\t四点\t00|4|4:00|时钟\tfour o’clock\t4|4:00|clock|four|o’clock|time\t
    🕟️\t5\t0\t四点半\t30|4|4:30|时间|钟\tfour-thirty\t30|4|4:30|clock|four|thirty|time\t
    🕔️\t5\t0\t五点\t00|5|5:00|时钟\tfive o’clock\t5|5:00|clock|five|o’clock|time\t
    🕠️\t5\t0\t五点半\t30|5|5:30|时钟\tfive-thirty\t30|5|5:30|clock|five|thirty|time\t
    🕕️\t5\t0\t六点\t00|6|6:00|时钟\tsix o’clock\t6|6:00|clock|o’clock|six|time\t
    🕡️\t5\t0\t六点半\t30|6|6:30|时钟\tsix-thirty\t30|6|6:30|clock|six|thirty\t
    🕖️\t5\t0\t七点\t00|7|7:00|时钟\tseven o’clock\t0|7|7:00|clock|o’clock|seven\t
    🕢️\t5\t0\t七点半\t30|7|7:30|时钟\tseven-thirty\t30|7|7:30|clock|seven|thirty\t
    🕗️\t5\t0\t八点\t00|8|8:00|时间|钟\teight o’clock\t8|8:00|clock|eight|o’clock|time\t
    🕣️\t5\t0\t八点半\t30|8|8:30|时钟\teight-thirty\t30|8|8:30|clock|eight|thirty|time\t
    🕘️\t5\t0\t九点\t00|9|9:00|时钟\tnine o’clock\t9|9:00|clock|nine|o’clock|time\t
    🕤️\t5\t0\t九点半\t30|9|9:30|时钟\tnine-thirty\t30|9|9:30|clock|nine|thirty|time\t
    🕙️\t5\t0\t十点\t00|10|10:00|时钟\tten o’clock\t0|10|10:00|clock|o’clock|ten\t
    🕥️\t5\t0\t十点半\t10|10:30|30|时钟\tten-thirty\t10|10:30|30|clock|ten|thirty|time\t
    🕚️\t5\t0\t十一点\t00|11|11:00|时钟\televen o’clock\t11|11:00|clock|eleven|o’clock|time\t
    🕦️\t5\t0\t十一点半\t11|11:30|30|时钟\televen-thirty\t11|11:30|30|clock|eleven|thirty|time\t
    🌑\t5\t0\t朔月\t新月|月亮\tnew moon\tdark|moon|new|space\t
    🌒\t5\t0\t蛾眉月\t三日月|娥眉月|弯月|月亮|盈月|眉月\twaxing crescent moon\tcrescent|dreams|moon|space|waxing\t
    🌓\t5\t0\t上弦月\t月亮\tfirst quarter moon\tfirst|moon|quarter|space\t
    🌔\t5\t0\t盈凸月\t月亮\twaxing gibbous moon\tgibbous|moon|space|waxing\t
    🌕️\t5\t0\t满月\t月亮|望月\tfull moon\tfull|moon|space\t
    🌖\t5\t0\t亏凸月\t月亮|衰落\twaning gibbous moon\tgibbous|moon|space|waning\t
    🌗\t5\t0\t下弦月\t月亮\tlast quarter moon\tlast|moon|quarter|space\t
    🌘\t5\t0\t残月\t亏眉月|弯月|月亮\twaning crescent moon\tcrescent|moon|space|waning\t
    🌙\t5\t0\t弯月\t娥眉月|新月形|月亮|残月|蛾眉月\tcrescent moon\tcrescent|moon|ramadan|space\t
    🌚\t5\t0\t微笑的朔月\t新月|月亮|朔月\tnew moon face\tface|moon|new|space\t
    🌛\t5\t0\t微笑的上弦月\t上弦月|月亮|蛾眉月\tfirst quarter moon face\tface|first|moon|quarter|space\t
    🌜️\t5\t0\t微笑的下弦月\t下弦月|月亮|残月\tlast quarter moon face\tdreams|face|last|moon|quarter\t
    🌡️\t5\t0\t温度计\t天气|气温|温度\tthermometer\tweather\t
    ☀️\t5\t0\t太阳\t光线|晴|晴天|阳光明媚|阳光普照\tsun\tbright|rays|space|sunny|weather\t
    🌝\t5\t0\t微笑的月亮\t月亮|望月|满月\tfull moon face\tbright|face|full|moon\t
    🌞\t5\t0\t微笑的太阳\t太阳|温暖阳光|阳光明媚\tsun with face\tbeach|bright|day|face|heat|shine|sun|sunny|sunshine|weather\t
    🪐\t5\t0\t有环行星\t土星|行星\tringed planet\tplanet|ringed|saturn|saturnine\t
    ⭐️\t5\t0\t星星\t五角星|白色星星\tstar\tastronomy|medium|stars|white\t
    🌟\t5\t0\t闪亮的星星\t发光|星星|闪亮|闪光\tglowing star\tglittery|glow|glowing|night|shining|sparkle|star|win\t
    🌠\t5\t0\t流星\t夜晚|太空|星空|陨落之星\tshooting star\tfalling|night|shooting|space|star\t
    🌌\t5\t0\t银河\t太空|星空\tmilky way\tmilky|space|way\t
    ☁️\t5\t0\t云\t云彩|云朵|天气|阴\tcloud\tweather\t
    ⛅️\t5\t0\t阴\t乌云蔽日|多云\tsun behind cloud\tbehind|cloud|cloudy|sun|weather\t
    ⛈️\t5\t0\t雷阵雨\t暴风雨|阵雨|雨|雷|雷暴\tcloud with lightning and rain\tcloud|lightning|rain|thunder|thunderstorm\t
    🌤️\t5\t0\t晴偶有云\t云|天气|太阳|少云|晴|阴\tsun behind small cloud\tbehind|cloud|sun|weather\t
    🌥️\t5\t0\t多云\t云|太阳|泠|阴\tsun behind large cloud\tbehind|cloud|sun|weather\t
    🌦️\t5\t0\t晴转雨\t下雨|云|天气|太阳|晴时多云偶阵雨|雨\tsun behind rain cloud\tbehind|cloud|rain|sun|weather\t
    🌧️\t5\t0\t下雨\t云|天气|雨\tcloud with rain\tcloud|rain|weather\t
    🌨️\t5\t0\t下雪\t云|天气|雪\tcloud with snow\tcloud|cold|snow|weather\t
    🌩️\t5\t0\t打雷\t云|天气|闪电|雷\tcloud with lightning\tcloud|lightning|weather\t
    🌪️\t5\t0\t龙卷风\t云|天气|旋风\ttornado\tcloud|weather|whirlwind\t
    🌫️\t5\t0\t雾\t云|霾\tfog\tcloud|weather\t
    🌬️\t5\t0\t大风\t狂风|风吹\twind face\tblow|cloud|face|wind\t
    🌀\t5\t0\t台风\t天气|旋风|晕|气旋|飓风|龙卷风\tcyclone\tdizzy|hurricane|twister|typhoon|weather\t
    🌈\t5\t0\t彩虹\tlgbt|双性恋|同志|跨性别\trainbow\tgay|genderqueer|glbt|glbtq|lesbian|lgbt|lgbtq|lgbtqia|nature|pride|queer|rain|trans|transgender|weather\t
    🌂\t5\t0\t收起的伞\t下雨|伞|雨|雨伞\tclosed umbrella\tclosed|clothing|rain|umbrella\t
    ☂️\t5\t0\t伞\t雨|雨伞\tumbrella\tclothing|rain\t
    ☔️\t5\t0\t雨伞\t下雨|伞|雨滴\tumbrella with rain drops\tclothing|drop|drops|rain|umbrella|weather\t
    ⛱️\t5\t0\t阳伞\t下雨|伞|地上的阳伞|太阳\tumbrella on ground\tground|rain|sun|umbrella\t
    ⚡️\t5\t0\t高压\t危险|有电|闪电\thigh voltage\tdanger|electric|electricity|high|lightning|nature|thunder|thunderbolt|voltage|zap\t
    ❄️\t5\t0\t雪花\t冷|天气|雪\tsnowflake\tcold|snow|weather\t
    ☃️\t5\t0\t雪与雪人\t泠|雪|雪人\tsnowman\tcold|man|snow\t
    ⛄️\t5\t0\t雪人\t下雪|泠\tsnowman without snow\tcold|man|snow|snowman\t
    ☄️\t5\t0\t彗星\t太空\tcomet\tspace\t
    🔥\t5\t0\t火焰\t火|烧|燃烧\tfire\taf|burn|flame|hot|lit|litaf|tool\t
    💧\t5\t0\t水滴\t冷|天气|水|泪|眼泪\tdroplet\tcold|comic|drop|nature|sad|sweat|tear|water|weather\t
    🌊\t5\t0\t浪花\t波浪|浪|海洋\twater wave\tnature|ocean|surf|surfer|surfing|water|wave\t
    🎃\t6\t0\t南瓜灯\t万圣节|南瓜|庆祝|灯|灯笼\tjack-o-lantern\tcelebration|halloween|jack|lantern|pumpkin\t
    🎄\t6\t0\t圣诞树\t圣诞|庆祝|树|装饰\tChristmas tree\tcelebration|christmas|tree\t
    🎆\t6\t0\t焰火\t庆典|庆祝|炮竹|烟花|爆竹\tfireworks\tboom|celebration|entertainment|yolo\t
    🎇\t6\t0\t烟花\t庆祝|火花|烟火|焰火\tsparkler\tboom|celebration|fireworks|sparkle\t
    🧨\t6\t0\t爆竹\t光亮|火花|炸药|烟火|烟花|爆炸|鞭炮\tfirecracker\tdynamite|explosive|fire|fireworks|light|pop|popping|spark\t
    ✨️\t6\t0\t闪亮\t星星|火花|闪光|闪耀\tsparkles\t*|magic|sparkle|star\t
    🎈\t6\t0\t气球\t庆祝|生日|节日\tballoon\tbirthday|celebrate|celebration\t
    🎉\t6\t0\t拉炮彩带\t兴奋|呱呱叫|庆祝|彩带|拉炮|派对|派对礼宾花|生日\tparty popper\tawesome|birthday|celebrate|celebration|excited|hooray|party|popper|tada|woohoo\t
    🎊\t6\t0\t五彩纸屑球\t五彩纸屑|庆祝|彩色纸屑|球|舞会\tconfetti ball\tball|celebrate|celebration|confetti|party|woohoo\t
    🎋\t6\t0\t七夕树\t七夕|庆祝|日本|条幅|树\ttanabata tree\tbanner|celebration|japanese|tanabata|tree\t
    🎍\t6\t0\t门松\t庆祝|日本|松树|盆栽|竹\tpine decoration\tbamboo|celebration|decoration|japanese|pine|plant\t
    🎎\t6\t0\t日本人形\t人偶|娃娃|庆祝|日本|日本人偶|节日\tJapanese dolls\tcelebration|doll|dolls|festival|japanese\t
    🎏\t6\t0\t鲤鱼旗\t庆祝|日本|男孩节|长旗\tcarp streamer\tcarp|celebration|streamer\t
    🎐\t6\t0\t风铃\t庆祝|铃铛|风\twind chime\tbell|celebration|chime|wind\t
    🎑\t6\t0\t赏月\t中秋|佳节|庆祝|月亮|祭月\tmoon viewing ceremony\tcelebration|ceremony|moon|viewing\t
    🧧\t6\t0\t红包\t利事|利是|好运|礼物|红信封|运气|钱\tred envelope\tenvelope|gift|good|hóngbāo|lai|luck|money|red|see\t
    🎀\t6\t0\t蝴蝶结\t丝带|庆祝|缎带\tribbon\tcelebration\t
    🎁\t6\t0\t礼物\t包礼物|包装|圣诞|庆祝|惊喜|生日礼物|盒子|礼品\twrapped gift\tbirthday|bow|box|celebration|christmas|gift|present|surprise|wrapped\t
    🎗️\t6\t0\t提示丝带\t丝带|庆典|庆祝|暗示|飘带\treminder ribbon\tcelebration|reminder|ribbon\t
    🎟️\t6\t0\t入场券\t票|门票\tadmission tickets\tadmission|ticket|tickets\t
    🎫\t6\t0\t票\t入场券|电影票|票根|车票|门票\tticket\tadmission|stub\t
    🎖️\t6\t0\t军功章\t军队|勋章|奖章\tmilitary medal\taward|celebration|medal|military\t
    🏆️\t6\t0\t奖杯\t冠军|奖励|奖品|奖赏|胜利|获胜\ttrophy\tchampion|champs|prize|slay|sport|victory|win|winning\t
    🏅\t6\t0\t奖牌\t获胜|运动会奖牌|运动员|金牌\tsports medal\taward|gold|medal|sports|winner\t
    🥇\t6\t0\t金牌\t奖牌|第一|第一名奖牌\t1st place medal\t1st|first|gold|medal|place\t
    🥈\t6\t0\t银牌\t亚军|奖牌|第二|第二名奖牌\t2nd place medal\t2nd|medal|place|second|silver\t
    🥉\t6\t0\t铜牌\t奖牌|季军|第三|第三名奖牌\t3rd place medal\t3rd|bronze|medal|place|third\t
    ⚽️\t6\t0\t足球\t大罗|梅西|球|球赛|罗纳尔多|胖罗|英式足球|运动\tsoccer ball\tball|football|futbol|soccer|sport\t
    ⚾️\t6\t0\t棒球\t球|运动\tbaseball\tball|sport\t
    🥎\t6\t0\t垒球\t手套|球|腋下|运动\tsoftball\tball|glove|sports|underarm\t
    🏀\t6\t0\t篮球\t打球|球|篮筐|运动\tbasketball\tball|hoop|sport\t
    🏐\t6\t0\t排球\t球|球赛\tvolleyball\tball|game\t
    🏈\t6\t0\t美式橄榄球\t橄榄球|球\tamerican football\tamerican|ball|bowl|football|sport|super\t
    🏉\t6\t0\t英式橄榄球\t橄榄球|球|运动\trugby football\tball|football|rugby|sport\t
    🎾\t6\t0\t网球\t球|球拍|网球拍\ttennis\tball|racquet|sport\t
    🥏\t6\t0\t飞盘\t圆盘|极限|极限运动|终极\tflying disc\tdisc|flying|ultimate\t
    🎳\t6\t0\t保龄球\t全倒|球|运动\tbowling\tball|game|sport|strike\t
    🏏\t6\t0\t板球\t球|球拍\tcricket game\tball|bat|cricket|game\t
    🏑\t6\t0\t曲棍球\t球|球棍|球赛\tfield hockey\tball|field|game|hockey|stick\t
    🏒\t6\t0\t冰球\t冰球杆|球|球棍\tice hockey\tgame|hockey|ice|puck|stick\t
    🥍\t6\t0\t袋棍球\t得分|球|球棍|球门|运动|长曲棍球\tlacrosse\tball|goal|sports|stick\t
    🏓\t6\t0\t乒乓球\t乒乓|桌球|比赛|球|球拍\tping pong\tball|bat|game|paddle|ping|pingpong|pong|table|tennis\t
    🏸\t6\t0\t羽毛球\t球拍|羽球\tbadminton\tbirdie|game|racquet|shuttlecock\t
    🥊\t6\t0\t拳击手套\t手套|拳击\tboxing glove\tboxing|glove\t
    🥋\t6\t0\t练武服\t制服|柔道|武术|空手道|跆拳道\tmartial arts uniform\tarts|judo|karate|martial|taekwondo|uniform\t
    🥅\t6\t0\t球门\t球网\tgoal net\tgoal|net\t
    ⛳️\t6\t0\t高尔夫球洞\t果岭|果岭旗|球洞|高尔夫|高球\tflag in hole\tflag|golf|hole|sport\t
    ⛸️\t6\t0\t滑冰\t冰刀|溜冰\tice skate\tice|skate|skating\t
    🎣\t6\t0\t钓鱼竿\t钓竿|鱼杆\tfishing pole\tentertainment|fish|fishing|pole|sport\t
    🤿\t6\t0\t潜水面罩\t浮潜|深潜|潜水\tdiving mask\tdiving|mask|scuba|snorkeling\t
    🎽\t6\t0\t运动背心\t上衣|跑步|运动服|饰带\trunning shirt\tathletics|running|sash|shirt\t
    🎿\t6\t0\t滑雪\t运动|雪\tskis\tski|snow|sport\t
    🛷\t6\t0\t雪橇\t下雪|乘雪橇|平底雪橇|驾雪橇\tsled\tluge|sledge|sleigh|snow|toboggan\t
    🥌\t6\t0\t冰壶\t冰上溜石|比赛|游戏|石壶\tcurling stone\tcurling|game|rock|stone\t
    🎯\t6\t0\t正中靶心的飞镖\t命中|标的|直接命中|要害|靶心|飞镖\tbullseye\tbull|dart|direct|entertainment|game|hit|target\t
    🪀\t6\t0\t悠悠球\t上下起落|溜溜球|犹豫不决|玩具\tyo-yo\tfluctuate|toy\t
    🪁\t6\t0\t风筝\t翱翔|飞翔\tkite\tfly|soar\t
    🔫\t6\t0\t水枪\t工具|左轮|手枪|枪|武器\twater pistol\tgun|handgun|pistol|revolver|tool|water|weapon\t
    🎱\t6\t0\t台球\t8 球制桌球|8号球|台球台|游戏|霹雳八球\tpool 8 ball\t8|8ball|ball|billiard|eight|game|pool\t
    🔮\t6\t0\t水晶球\t命运|工具|梦幻|水晶|球|童话|财富|魔法\tcrystal ball\tball|crystal|fairy|fairytale|fantasy|fortune|future|magic|tale|tool\t
    🪄\t6\t0\t魔棒\t女巫|巫师|魔术|魔术师|魔杖|魔法\tmagic wand\tmagic|magician|wand|witch|wizard\t
    🎮️\t6\t0\t游戏手柄\t手柄|游戏|游戏控制器|电子游戏\tvideo game\tcontroller|entertainment|game|video\t
    🕹️\t6\t0\t游戏操控杆\t操控杆|游戏|电子游戏\tjoystick\tgame|video|videogame\t
    🎰\t6\t0\t老虎机\t吃角子老虎|游戏|角子机|赌博|赌场\tslot machine\tcasino|gamble|gambling|game|machine|slot|slots\t
    🎲\t6\t0\t骰子\t掷骰子|色子|骰子游戏\tgame die\tdice|die|entertainment|game\t
    🧩\t6\t0\t拼图\t图片|智力游戏|相扣|线索|联锁|部件\tpuzzle piece\tclue|interlocking|jigsaw|piece|puzzle\t
    🧸\t6\t0\t泰迪熊\t填充|毛绒玩具|熊|玩偶|玩具|玩物|长毛绒\tteddy bear\tbear|plaything|plush|stuffed|teddy|toy\t
    🪅\t6\t0\t彩罐\t五月节|墨西哥|庆祝|皮纳塔|糖果|聚会|节日\tpiñata\tcandy|celebrate|celebration|cinco|de|festive|mayo|party|pinada|pinata\t
    🪩\t6\t0\t镜球\t派对|聚会|舞会|舞厅|舞蹈|蹦迪|迪斯科|闪耀\tmirror ball\tball|dance|disco|glitter|mirror|party\t
    🪆\t6\t0\t套娃\t俄罗斯套娃|俄罗斯娃娃|娃娃\tnesting dolls\tbabooshka|baboushka|babushka|doll|dolls|matryoshka|nesting|russia\t
    ♠️\t6\t0\t黑桃\t扑克|牌|葵扇|黑桃花色\tspade suit\tcard|game|spade|suit\t
    ♥️\t6\t0\t红桃\t扑克|牌|红心|红桃花色\theart suit\tcard|emotion|game|heart|hearts|suit\t
    ♦️\t6\t0\t方片\t扑克|方块|牌|牌局\tdiamond suit\tcard|diamond|game|suit\t
    ♣️\t6\t0\t梅花\t扑克|梅花花色|牌|草花\tclub suit\tcard|club|clubs|game|suit\t
    ♟️\t6\t0\t兵\t受骗者|国际象棋|牺牲品\tchess pawn\tchess|dupe|expendable|pawn\t
    🃏\t6\t0\t大小王\t大王|小丑|小王|扑克|扑克小丑|牌|百搭牌|鬼牌\tjoker\tcard|game|wildcard\t
    🀄️\t6\t0\t红中\t方城之战|牌局|麻将|麻将红中\tmahjong red dragon\tdragon|game|mahjong|red\t
    🎴\t6\t0\t花札\t卡牌|日本|游戏|花斗|花牌\tflower playing cards\tcard|cards|flower|game|japanese|playing\t
    🎭️\t6\t0\t表演艺术\t剧院|女演员|戏剧|演员|艺术|莎士比亚|表演|面具\tperforming arts\tactor|actress|art|arts|entertainment|mask|performing|theater|theatre|thespian\t
    🖼️\t6\t0\t带框的画\t加框的照片|博物馆|框|照片|画|画框|艺术\tframed picture\tart|frame|framed|museum|painting|picture\t
    🎨\t6\t0\t调色盘\t创意|博物馆|多种色彩|娱乐|画家|画画|绘画|艺术|调色板\tartist palette\tart|artist|artsy|arty|colorful|creative|entertainment|museum|painter|painting|palette\t
    🧵\t6\t0\t线\t卷盘|线轴|绳子|缝纫|针|针线\tthread\tneedle|sewing|spool|string\t
    🪡\t6\t0\t缝合针\t线|绣花针|缝合|缝纫|缝线|缝衣针|裁剪|针\tsewing needle\tembroidery|needle|sew|sewing|stitches|sutures|tailoring|thread\t
    🧶\t6\t0\t毛线\t毛线球|线球|编织|钩针编织\tyarn\tball|crochet|knit\t
    🪢\t6\t0\t结\t八字结|打结|绳子|绳扣|绳结|缠结|麻线\tknot\tcord|rope|tangled|tie|twine|twist\t
    👓️\t7\t0\t眼镜\t服饰|眼睛\tglasses\tclothing|eye|eyeglasses|eyewear\t
    🕶️\t7\t0\t墨镜\t太阳镜\tsunglasses\tdark|eye|eyewear|glasses\t
    🥽\t7\t0\t护目镜\t护目|护眼|水肺|游泳|潜水|焊接\tgoggles\tdive|eye|protection|scuba|swimming|welding\t
    🥼\t7\t0\t白大褂\t医生|外衣|实验|实验人员|实验室白大褂|实验服|白衣|科学家|衣服\tlab coat\tclothes|coat|doctor|dr|experiment|jacket|lab|scientist|white\t
    🦺\t7\t0\t救生衣\t安全|紧急|背心|逃生\tsafety vest\temergency|safety|vest\t
    👔\t7\t0\t领带\t工作|正式|衬衫领带\tnecktie\tclothing|employed|serious|shirt|tie\t
    👕\t7\t0\tT恤\tt恤|休闲服装|恤衫\tt-shirt\tblue|casual|clothes|clothing|collar|dressed|shirt|shopping|tshirt|weekend\t
    👖\t7\t0\t牛仔裤\t休闲|周末|蓝色|裤子\tjeans\tblue|casual|clothes|clothing|denim|dressed|pants|shopping|trousers|weekend\t
    🧣\t7\t0\t围巾\t冷|包紧|围脖|头巾\tscarf\tbundle|cold|neck|up\t
    🧤\t7\t0\t手套\t手\tgloves\thand\t
    🧥\t7\t0\t外套\t冷|夹克|超冷\tcoat\tbrr|bundle|cold|jacket|up\t
    🧦\t7\t0\t袜子\t短袜|袜|长袜\tsocks\tstocking\t
    👗\t7\t0\t连衣裙\t衣服|裙子\tdress\tclothes|clothing|dressed|fancy|shopping\t
    👘\t7\t0\t和服\t日本|衣服\tkimono\tclothing|comfortable\t
    🥻\t7\t0\t纱丽\t印度|披肩|莎丽|衣服|连衣裙\tsari\tclothing|dress\t
    🩱\t7\t0\t连体泳衣\t一片式|泳衣|泳装|游泳|连身泳衣\tone-piece swimsuit\tbathing|one-piece|suit|swimsuit\t
    🩲\t7\t0\t三角裤\t一片式|内裤|泳衣|泳装|短裤\tbriefs\tbathing|one-piece|suit|swimsuit|underwear\t
    🩳\t7\t0\t短裤\t内裤|四角裤|泳衣|泳装|泳裤|裤子\tshorts\tbathing|pants|suit|swimsuit|underwear\t
    👙\t7\t0\t比基尼\t三点式|泳装|游泳\tbikini\tbathing|beach|clothing|pool|suit|swim\t
    👚\t7\t0\t女装\t女|女生衣服|女衬衫|衣服\twoman’s clothes\tblouse|clothes|clothing|collar|dress|dressed|lady|shirt|shopping|woman|woman’s\t
    🪭\t7\t0\t折扇\t凉|凉快|啪嗒声|害羞|扇|扇动|扇子|拍手|热|羞涩|腼腆|舞蹈|调情|跳舞|降温\tfolding hand fan\tclack|clap|cool|cooling|dance|fan|flirt|flutter|folding|hand|hot|shy\t
    👛\t7\t0\t钱包\t血拼|铜板\tpurse\tclothes|clothing|coin|dress|fancy|handbag|shopping\t
    👜\t7\t0\t手提包\t包包|挎包|血拼\thandbag\tbag|clothes|clothing|dress|lady|purse|shopping\t
    👝\t7\t0\t手袋\t包|化妆包|手拿|手拿包\tclutch bag\tbag|clothes|clothing|clutch|dress|handbag|pouch|purse\t
    🛍️\t7\t0\t购物袋\t包|袋|购物|逛街\tshopping bags\tbag|bags|hotel|shopping\t
    🎒\t7\t0\t书包\t上学|包\tbackpack\tbackpacking|bag|bookbag|education|rucksack|satchel|school\t
    🩴\t7\t0\t夹趾凉鞋\t人字拖|凉鞋|沙滩|沙滩凉鞋|草屡|鞋\tthong sandal\tbeach|flip|flop|sandal|sandals|shoe|thong|thongs|zōri\t
    👞\t7\t0\t男鞋\t棕色|皮鞋|鞋\tman’s shoe\tbrown|clothes|clothing|feet|foot|kick|man|man’s|shoe|shoes|shopping\t
    👟\t7\t0\t跑鞋\t跑|运动鞋|鞋\trunning shoe\tathletic|clothes|clothing|fast|kick|running|shoe|shoes|shopping|sneaker|tennis\t
    🥾\t7\t0\t登山鞋\t健行|徒步|户外|登山|背包|远足野营|露营|靴子|鞋\thiking boot\tbackpacking|boot|brown|camping|hiking|outdoors|shoe\t
    🥿\t7\t0\t平底鞋\t一脚蹬|便鞋|平底芭蕾舞鞋|芭蕾舞鞋\tflat shoe\tballet|comfy|flat|flats|shoe|slip-on|slipper\t
    👠\t7\t0\t高跟鞋\t女|时装|鞋|高跟\thigh-heeled shoe\tclothes|clothing|dress|fashion|heel|heels|high-heeled|shoe|shoes|shopping|stiletto|woman\t
    👡\t7\t0\t女式凉鞋\t凉鞋|女\twoman’s sandal\tclothing|sandal|shoe|woman|woman’s\t
    🩰\t7\t0\t芭蕾舞鞋\t舞蹈|舞鞋|足尖鞋|跳舞\tballet shoes\tballet|dance|shoes\t
    👢\t7\t0\t女靴\t女|女式靴子|靴子\twoman’s boot\tboot|clothes|clothing|dress|shoe|shoes|shopping|woman|woman’s\t
    🪮\t7\t0\t发夹\t圆蓬|头发|夹子|小刷子|梳子|梳理|爆炸头|非洲头\thair pick\tafro|comb|groom|hair|pick\t
    👑\t7\t0\t皇冠\t国王|权力的游戏|王冠|王后|皇家\tcrown\tclothing|family|king|medieval|queen|royal|royalty|win\t
    👒\t7\t0\t女帽\t女|女式|帽子|花园派对\twoman’s hat\tclothes|clothing|garden|hat|hats|party|woman|woman’s\t
    🎩\t7\t0\t礼帽\t帽子|正式|高帽\ttop hat\tclothes|clothing|fancy|formal|hat|magic|top|tophat\t
    🎓️\t7\t0\t毕业帽\t四方帽|学位|学者|毕业\tgraduation cap\tcap|celebration|clothing|education|graduation|hat|scholar\t
    🧢\t7\t0\t鸭舌帽\t帽子|棒球帽\tbilled cap\tbaseball|bent|billed|cap|dad|hat\t
    🪖\t7\t0\t军用头盔\t军事|军用|军队|士兵|头盔|战争|战士|部队\tmilitary helmet\tarmy|helmet|military|soldier|war|warrior\t
    ⛑️\t7\t0\t白十字头盔\t十字|头盔|安全帽|救援人员头盔|脸\trescue worker’s helmet\taid|cross|face|hat|helmet|rescue|worker’s\t
    📿\t7\t0\t念珠\t宗教|珠子|祈祷|项链\tprayer beads\tbeads|clothing|necklace|prayer|religion\t
    💄\t7\t0\t唇膏\t化妆|化妆品|口红|约会\tlipstick\tcosmetics|date|makeup\t
    💍\t7\t0\t戒指\t结婚|订婚|钻戒|闪\tring\tdiamond|engaged|engagement|married|romance|shiny|sparkling|wedding\t
    💎\t7\t0\t宝石\t婚礼|珠宝|订婚|钻石\tgem stone\tdiamond|engagement|gem|jewel|money|romance|stone|wedding\t
    🔇\t7\t0\t已静音的扬声器\t声音|安静|扬声器|扬声器关闭|无声|静音\tmuted speaker\tmute|muted|quiet|silent|sound|speaker\t
    🔈️\t7\t0\t低音量的扬声器\t低音量扬扬声|喇叭|小声|小音量|扬声器|轻声|音量\tspeaker low volume\tlow|soft|sound|speaker|volume\t
    🔉\t7\t0\t中等音量的扬声器\t中等|中等音量|中音量|中音量扬声器|扬声器\tspeaker medium volume\tmedium|sound|speaker|volume\t
    🔊\t7\t0\t高音量的扬声器\t大声|大音量|扬声器|音量|高音量\tspeaker high volume\thigh|loud|music|sound|speaker|volume\t
    📢\t7\t0\t喇叭\t公共广播|大声|广播|扩音器|通知\tloudspeaker\taddress|communication|loud|public|sound\t
    📣\t7\t0\t扩音器\t呼喊|喇叭|喇叭筒|大声|通知\tmegaphone\tcheering|sound\t
    📯\t7\t0\t邮号\t号|号角|喇叭|邮政\tpostal horn\thorn|post|postal\t
    🔔\t7\t0\t铃铛\t叮当|响铃|钟|钟声|铃声\tbell\tbreak|church|sound\t
    🔕\t7\t0\t禁止响铃\t响铃关闭|安静|无声|铃|静音\tbell with slash\tbell|forbidden|mute|no|not|prohibited|quiet|silent|slash|sound\t
    🎼\t7\t0\t乐谱\t五线谱|曲谱|音乐|音符\tmusical score\tmusic|musical|note|score\t
    🎵\t7\t0\t音符\t乐谱|五线谱|八分音符|音乐\tmusical note\tmusic|musical|note|sound\t
    🎶\t7\t0\t多个音符\t乐谱|五线谱|八分音符|音乐|音符\tmusical notes\tmusic|musical|note|notes|sound\t
    🎙️\t7\t0\t录音室麦克风\t录音室|音乐|麦|麦克|麦克风\tstudio microphone\tmic|microphone|music|studio\t
    🎚️\t7\t0\t电平滑块\t滑块|电平|调节|调节滑块|音乐|音量\tlevel slider\tlevel|music|slider\t
    🎛️\t7\t0\t控制旋钮\t控制|旋钮|调节|音乐\tcontrol knobs\tcontrol|knobs|music\t
    🎤\t7\t0\t麦克风\tk歌|卡拉ok|唱k|唱歌|麦|麦克\tmicrophone\tkaraoke|mic|music|sing|sound\t
    🎧️\t7\t0\t耳机\t头戴式耳机|耳塞\theadphone\tearbud|sound\t
    📻️\t7\t0\t收音机\t娱乐|广播|广播电台|无线电|电台\tradio\tentertainment|tbt|video\t
    🎷\t7\t0\t萨克斯管\t乐器|吹奏|演奏|萨克斯风|音乐\tsaxophone\tinstrument|music|sax\t
    🎺\t7\t0\t小号\t乐器|吹奏|喇叭|音乐\ttrumpet\tinstrument|music\t
    🪗\t7\t0\t手风琴\t乐器|六角形风琴|音乐|风琴\taccordion\tbox|concertina|instrument|music|squeeze|squeezebox\t
    🎸\t7\t0\t吉他\t乐器|弹奏|演奏|电吉他|音乐\tguitar\tinstrument|music|strat\t
    🎹\t7\t0\t音乐键盘\t乐器|弹奏|演奏|钢琴|音乐\tmusical keyboard\tinstrument|keyboard|music|musical|piano\t
    🎻\t7\t0\t小提琴\t乐器|提琴|是特拉迪瓦尔|演奏|音乐\tviolin\tinstrument|music\t
    🪕\t7\t0\t班卓琴\t弦乐器|弹奏|音乐\tbanjo\tmusic|stringed\t
    🥁\t7\t0\t鼓\t音乐|鼓声|鼓槌\tdrum\tdrumsticks|music\t
    🪘\t7\t0\t长鼓\t乐器|康加鼓|康茄鼓|敲|节奏|非洲手鼓|鼓\tlong drum\tbeat|conga|drum|instrument|long|rhythm\t
    🪇\t7\t0\t沙球\t乐器|恰恰|打击乐器|拨浪鼓|摇|摇动|沙槌|沙铃|派对|舞蹈|音乐\tmaracas\tcha|dance|instrument|music|party|percussion|rattle|shake|shaker\t
    🪈\t7\t0\t长笛\t乐器|乐队|木管乐器|横笛|短笛|竖笛|管乐器|菲菲笛|长笛手|音乐\tflute\tband|fife|flautist|instrument|marching|music|orchestra|piccolo|pipe|recorder|woodwind\t
    🪉\t7\t1\t竖琴\t丘比特|乐器|爱|管弦乐队|音乐\tharp\tcupid|instrument|love|music|orchestra\t
    📱\t7\t0\t手机\t手提电话|智能手机|电话|移动|移动电话|移动通信|通信\tmobile phone\tcell|communication|mobile|phone|telephone\t
    📲\t7\t0\t带有箭头的手机\t手机|接收|智能手机|来电|电话|移动电话|箭头|通信\tmobile phone with arrow\tarrow|build|call|cell|communication|mobile|phone|receive|telephone\t
    ☎️\t7\t0\t电话\t固定电话|固话|座机\ttelephone\tphone\t
    📞\t7\t0\t电话听筒\t听筒|固定电话|固话|座机|电话|通信\ttelephone receiver\tcommunication|phone|receiver|telephone|voip\t
    📟️\t7\t0\t寻呼机\tbb 机|传呼机|呼机|通信\tpager\tcommunication\t
    📠\t7\t0\t传真机\t传真|传真号|发传真\tfax machine\tcommunication|fax|machine\t
    🔋\t7\t0\t电池\t正极|电|电极|电源|蓄电池|负极\tbattery\tbattery\t
    🪫\t7\t0\t电池电量不足\t低能量|电子|电池|电池电量低|电量不足\tlow battery\tbattery|drained|electronic|energy|low|power\t
    🔌\t7\t0\t电源插头\t插头|电插头|电源|电线\telectric plug\telectric|electricity|plug\t
    💻️\t7\t0\t笔记本电脑\tpc|个人电脑|手提电脑|电脑\tlaptop\tcomputer|office|pc|personal\t
    🖥️\t7\t0\t台式电脑\tpc|个人电脑|台式|显示器|显示屏|电脑|计算机\tdesktop computer\tcomputer|desktop|monitor\t
    🖨️\t7\t0\t打印机\t印刷机|喷墨打印|复印|打印|扫描|激光打印\tprinter\tcomputer\t
    ⌨️\t7\t0\t键盘\t打字|按键|电脑|输入\tkeyboard\tcomputer\t
    🖱️\t7\t0\t电脑鼠标\t有线鼠标|激光鼠标|点击|点按|电脑|鼠标\tcomputer mouse\tcomputer|mouse\t
    🖲️\t7\t0\t轨迹球\t有线鼠标|电脑|追踪球|鼠标\ttrackball\tcomputer\t
    💽\t7\t0\t电脑光盘\tmd|minidisk|mini光盘|光盘|电脑|迷你光盘|迷你光碟|迷你唱片\tcomputer disk\tcomputer|disk|minidisk|optical\t
    💾\t7\t0\t软盘\t3.5英寸|便携|存储|电脑|磁盘\tfloppy disk\tcomputer|disk|floppy\t
    💿️\t7\t0\t光盘\tcd|专辑|存储|影片|蓝光|音乐\toptical disk\tblu-ray|cd|computer|disk|dvd|optical\t
    📀\t7\t0\tDVD\tdvd|光盘|光碟|影片|电脑|蓝光|音乐\tdvd\tblu-ray|cd|computer|disk|optical\t
    🧮\t7\t0\t算盘\t计算|计算器\tabacus\tcalculation|calculator\t
    🎥\t7\t0\t电影摄影机\t录像|摄像机|摄录机|摄影|摄影机|电影\tmovie camera\tbollywood|camera|cinema|film|hollywood|movie|record\t
    🎞️\t7\t0\t影片帧\t帧|电影|电影胶卷|电影胶片|胶卷|胶片\tfilm frames\tcinema|film|frames|movie\t
    📽️\t7\t0\t电影放映机\t影片|投影仪|放映机|电影|视频\tfilm projector\tcinema|film|movie|projector|video\t
    🎬️\t7\t0\t场记板\t场记|打板|拍电影\tclapper board\taction|board|clapper|movie\t
    📺️\t7\t0\t电视机\t电视|看电视|节目|视频\ttelevision\ttv|video\t
    📷️\t7\t0\t相机\t卡片相机|拍照|摄影|照片|照相机|自拍\tcamera\tphoto|selfie|snap|tbt|trip|video\t
    📸\t7\t0\t开闪光灯的相机\t带闪光灯的相机|拍照|相机|闪光灯|闪光灯打开\tcamera with flash\tcamera|flash|video\t
    📹️\t7\t0\t摄像机\t录像|录像机|录影|拍摄|摄影机|视频\tvideo camera\tcamcorder|camera|tbt|video\t
    📼\t7\t0\t录像带\tvhs|录影带|磁带\tvideocassette\told|school|tape|vcr|vhs|video\t
    🔍️\t7\t0\t左斜的放大镜\t工具|搜索|放大|放大镜|查找\tmagnifying glass tilted left\tglass|lab|left|left-pointing|magnifying|science|search|tilted|tool\t
    🔎\t7\t0\t右斜的放大镜\t工具|搜索|放大|放大镜|查找\tmagnifying glass tilted right\tcontact|glass|lab|magnifying|right|right-pointing|science|search|tilted|tool\t
    🕯️\t7\t0\t蜡烛\t光|烛光|烛火|照明|燃烧\tcandle\tlight\t
    💡\t7\t0\t灯泡\t主意|想法|点子|电|电灯泡|白炽灯\tlight bulb\tbulb|comic|electric|idea|light\t
    🔦\t7\t0\t手电筒\t光|工具|手电|照明|电筒\tflashlight\telectric|light|tool|torch\t
    🏮\t7\t0\t红灯笼\t光|喜庆|居酒屋|日本|灯笼|节日|酒馆|餐馆\tred paper lantern\tbar|lantern|light|paper|red|restaurant\t
    🪔\t7\t0\t印度油灯\t排灯节|油|灯|迪亚\tdiya lamp\tdiya|lamp|light|oil\t
    📔\t7\t0\t精装笔记本\t书|写作|学校|封面|教育|笔记本\tnotebook with decorative cover\tbook|cover|decorated|decorative|education|notebook|school|writing\t
    📕\t7\t0\t合上的书本\t书|书本|书本合起|合上\tclosed book\tbook|closed|education\t
    📖\t7\t0\t打开的书本\t书|书本|图书馆|小说|开卷|打开|知识|读书|阅读\topen book\tbook|education|fantasy|knowledge|library|novels|open|reading\t
    📗\t7\t0\t绿色书本\t书|书本|图书馆|教育|绿|绿皮书|绿色|阅读\tgreen book\tbook|education|fantasy|green|library|reading\t
    📘\t7\t0\t蓝色书本\t书|书本|图书馆|教育|篮|蓝皮书|蓝色|阅读\tblue book\tblue|book|education|fantasy|library|reading\t
    📙\t7\t0\t橙色书本\t书|书本|图书馆|教育|橘皮书|橘色|橙色|阅读\torange book\tbook|education|fantasy|library|orange|reading\t
    📚️\t7\t0\t书\t书本|书籍|图书|图书馆|学习|学校|小说|教育|知识|阅读\tbooks\tbook|education|fantasy|knowledge|library|novels|reading|school|study\t
    📓\t7\t0\t笔记本\t日记本|本子|笔记|记事本|记录\tnotebook\tnotebook\t
    📒\t7\t0\t账本\t笔记本|记事本|记账|账簿\tledger\tnotebook\t
    📃\t7\t0\t带卷边的页面\t卷曲|卷边|文书|文件|文档|纸张|页面\tpage with curl\tcurl|document|page|paper\t
    📜\t7\t0\t卷轴\t卷纸|画卷|纸|纸卷|羊皮纸\tscroll\tpaper\t
    📄\t7\t0\t文件\t文书|文档|页面向上\tpage facing up\tdocument|facing|page|paper|up\t
    📰\t7\t0\t报纸\t传播|报道|新闻|看报|纸|读报\tnewspaper\tcommunication|news|paper\t
    🗞️\t7\t0\t报纸卷\t卷起|卷起的报纸|报纸|新闻|纸\trolled-up newspaper\tnews|newspaper|paper|rolled|rolled-up\t
    📑\t7\t0\t标签页\t书签|书签页标签|有书签的页面|标签\tbookmark tabs\tbookmark|mark|marker|tabs\t
    🔖\t7\t0\t书签\t标签|读书|阅读\tbookmark\tmark\t
    🏷️\t7\t0\t标签\t吊牌|标记|行李牌\tlabel\ttag\t
    🪙\t7\t0\t硬币\t富有|欧元|美元|财富|金|金属|金币|钱|银\tcoin\tdollar|euro|gold|metal|money|rich|silver|treasure\t
    💰️\t7\t0\t钱袋\t付钱|十亿|变现|守财奴|富有|有钱|现金|百万|美元|赌钱|赢钱|钱|钱包|银行\tmoney bag\tbag|bank|bet|billion|cash|cost|dollar|gold|million|money|moneybag|paid|paying|pot|rich|win\t
    💴\t7\t0\t日元\t日币|现金|纸币|货币|钞票|钱|银行\tyen banknote\tbank|banknote|bill|currency|money|note|yen\t
    💵\t7\t0\t美元\t现金|纸币|美刀|美钞|货币|钱|银行\tdollar banknote\tbank|banknote|bill|currency|dollar|money|note\t
    💶\t7\t0\t欧元\t现金|纸币|货币|钞票|钱|银行\teuro banknote\t100|bank|banknote|bill|currency|euro|money|note|rich\t
    💷\t7\t0\t英镑\t现金|纸币|货币|钞票|钱|银行\tpound banknote\tbank|banknote|bill|billion|cash|currency|money|note|pound|pounds\t
    💸\t7\t0\t长翅膀的钱\t纸币|翅膀|花钱|钱|飞\tmoney with wings\tbank|banknote|bill|billion|cash|dollar|fly|million|money|note|pay|wings\t
    💳️\t7\t0\t信用卡\t信用|借记卡|刷卡|卡|收钱|现金|现金卡|贷记卡|银行|银行卡\tcredit card\tbank|card|cash|charge|credit|money|pay\t
    🧾\t7\t0\t收据\t会计|信封|凭据|发票|收条|簿记|记账|证据|证明|账单\treceipt\taccounting|bookkeeping|evidence|invoice|proof\t
    💹\t7\t0\t趋势向上且带有日元符号的图表\t上扬|上涨|日元|日元升值|日元汇率|日币|货币|货币升值图表|走势\tchart increasing with yen\tbank|chart|currency|graph|growth|increasing|market|money|rise|trend|upward|yen\t
    ✉️\t7\t0\t信封\t信件|信息|来信|电子邮件|电邮|邮件\tenvelope\te-mail|email|letter\t
    📧\t7\t0\t电子邮件\t信件|信封|电邮|邮件\te-mail\temail|letter|mail\t
    📨\t7\t0\t来信\t信件|信封|发送|接收|收信|收到来信|收到邮件|电子邮件|电邮|邮件\tincoming envelope\tdelivering|e-mail|email|envelope|incoming|letter|mail|receive|sent\t
    📩\t7\t0\t收邮件\t信件|信封|发信|发出|发送|发邮件|有箭头的信封|邮件\tenvelope with arrow\tarrow|communication|down|e-mail|email|envelope|letter|mail|outgoing|send|sent\t
    📤️\t7\t0\t发件箱\t信件|发信|发送|发邮件|收件箱|电子邮件|电邮|邮件\toutbox tray\tbox|email|letter|mail|outbox|sent|tray\t
    📥️\t7\t0\t收件箱\t信件|接收|收信|收到邮件|电子邮件|电邮|邮件\tinbox tray\tbox|email|inbox|letter|mail|receive|tray|zero\t
    📦️\t7\t0\t包裹\t快递|指向|盒子|箱子|装货|运送\tpackage\tbox|communication|delivery|parcel|shipping\t
    📫️\t7\t0\t有待收信件\t信箱|旗标|有新信件|邮箱|邮箱关闭红旗升起\tclosed mailbox with raised flag\tclosed|communication|flag|mail|mailbox|postbox|raised\t
    📪️\t7\t0\t无待收信件\t信箱|信箱关闭红旗放下|放下|旗标|无新信件\tclosed mailbox with lowered flag\tclosed|flag|lowered|mail|mailbox|postbox\t
    📬️\t7\t0\t有新信件\t信箱|信箱打开红旗升起|打开|旗标|有待收信件\topen mailbox with raised flag\tflag|mail|mailbox|open|postbox|raised\t
    📭️\t7\t0\t无新信件\t信箱|信箱打开|信箱打开红旗放下|旗标|无待收信件|邮件|邮递\topen mailbox with lowered flag\tflag|lowered|mail|mailbox|open|postbox\t
    📮\t7\t0\t邮筒\t信|信箱|寄信|邮箱\tpostbox\tmail|mailbox\t
    🗳️\t7\t0\t投票箱\t投票|盒子|票箱|选举|选票\tballot box with ballot\tballot|box\t
    ✏️\t7\t0\t铅笔\t橡皮|橡皮擦|画画|画笔|笔|绘画\tpencil\tpencil\t
    ✒️\t7\t0\t钢笔尖\t写字|硬笔|笔|笔尖|钢笔|黑色笔尖\tblack nib\tblack|nib|pen\t
    🖋️\t7\t0\t钢笔\t写字|硬笔|笔\tfountain pen\tfountain|pen\t
    🖊️\t7\t0\t笔\t原子笔|圆珠笔|油笔\tpen\tballpoint\t
    🖌️\t7\t0\t画笔\t刷|毛笔|画刷|笔刷\tpaintbrush\tpainting\t
    🖍️\t7\t0\t蜡笔\t油画棒|画棒\tcrayon\tcrayon\t
    📝\t7\t0\t备忘录\t便条|便条簿|便笺|铅笔\tmemo\tcommunication|media|notes|pencil\t
    💼\t7\t0\t公文包\t上班|公事包|办公室|包|手提包|文件\tbriefcase\toffice\t
    📁\t7\t0\t文件夹\t办公|文件|文具|硬纸夹\tfile folder\tfile|folder\t
    📂\t7\t0\t打开的文件夹\t办公|打开|打开文件夹|文件|文件夹|文具\topen file folder\tfile|folder|open\t
    🗂️\t7\t0\t索引分隔文件夹\t分隔|分隔卡|文件夹|索引|隔板\tcard index dividers\tcard|dividers|index\t
    📅\t7\t0\t日历\t日期\tcalendar\tdate\t
    📆\t7\t0\t手撕日历\t日历|日期\ttear-off calendar\tcalendar|tear-off\t
    🗒️\t7\t0\t线圈本\t文具|笔记本|线圈|记事本\tspiral notepad\tnote|notepad|pad|spiral\t
    🗓️\t7\t0\t线圈日历\t日历|日期|线圈|记事本\tspiral calendar\tcalendar|pad|spiral\t
    📇\t7\t0\t卡片索引\t卡片|卡牌索引|名片索引|目录|索引\tcard index\tcard|index|old|rolodex|school\t
    📈\t7\t0\t趋势向上的图表\t上升|上涨|上涨图表|上涨趋势线|向上|图表|成长|趋势线\tchart increasing\tchart|data|graph|growth|increasing|right|trend|up|upward\t
    📉\t7\t0\t趋势向下的图表\t下跌|下跌图表|下跌趋势线|下降|向下|图表|趋势线\tchart decreasing\tchart|data|decreasing|down|downward|graph|negative|trend\t
    📊\t7\t0\t条形图\t图形|图表|柱形图|直方图|资料|长条图\tbar chart\tbar|chart|data|graph\t
    📋️\t7\t0\t剪贴板\t写字夹板|写字板|剪贴簿|夹子|待办事项|待办表|纸张\tclipboard\tdo|list|notes\t
    📌\t7\t0\t图钉\t固定|拼贴|按钉\tpushpin\tcollage|pin\t
    📍\t7\t0\t圆图钉\t位置|固定|图钉\tround pushpin\tlocation|map|pin|pushpin|round\t
    📎\t7\t0\t回形针\t万字夹|回纹针|曲别针|纸夹\tpaperclip\tpaperclip\t
    🖇️\t7\t0\t连起来的两个回形针\t万字夹|回形针|回纹针|曲别针|纸夹|连接|连接的回形针\tlinked paperclips\tlink|linked|paperclip|paperclips\t
    📏\t7\t0\t直尺\t尺|尺子|数学|文具|测量|量|长度\tstraight ruler\tangle|edge|math|ruler|straight|straightedge\t
    📐\t7\t0\t三角尺\t三角|尺|数学|文具|测量|角|角度\ttriangular ruler\tangle|math|rule|ruler|set|slide|triangle|triangular\t
    ✂️\t7\t0\t剪刀\t修剪|剪|剪子|剪裁|工具\tscissors\tcut|cutting|paper|tool\t
    🗃️\t7\t0\t卡片盒\t卡片|存档|文件|标签|档案|箱|索引\tcard file box\tbox|card|file\t
    🗄️\t7\t0\t文件柜\t存档|归档|收纳|柜|档案\tfile cabinet\tcabinet|file|filing|paper\t
    🗑️\t7\t0\t垃圾桶\t垃圾|垃圾篓|废纸篓\twastebasket\tcan|garbage|trash|waste\t
    🔒️\t7\t0\t合上的锁\t上锁|私密|锁|锁住|锁头|锁定\tlocked\tclosed|lock|private\t
    🔓️\t7\t0\t打开的锁\t取消锁定|开锁|打开|破解|解锁|锁\tunlocked\tcracked|lock|open|unlock\t
    🔏\t7\t0\t墨水笔和锁\t笔|笔尖|钢笔|锁|隐私\tlocked with pen\tink|lock|locked|nib|pen|privacy\t
    🔐\t7\t0\t钥匙和锁\t安全|脚踏车锁|钥匙|锁|锁上\tlocked with key\tbike|closed|key|lock|locked|secure\t
    🔑\t7\t0\t钥匙\t密码|密钥|开锁|解锁|锁\tkey\tkeys|lock|major|password|unlock\t
    🗝️\t7\t0\t老式钥匙\t古老的钥匙|旧钥匙|线索|钥匙\told key\tclue|key|lock|old\t
    🔨\t7\t0\t锤子\t修理|家居修缮|工具|敲|施工|砸|铁锤\thammer\thome|improvement|repairs|tool\t
    🪓\t7\t0\t斧头\t切|劈|木头|砍\taxe\tax|chop|hatchet|split|wood\t
    ⛏️\t7\t0\t铁镐\t工具|挖|挖掘|采矿|锄头|鹤嘴锄\tpick\thammer|mining|tool\t
    ⚒️\t7\t0\t锤子与镐\t工具|铁锤|铁镐|锤子|镐|镐子\thammer and pick\thammer|pick|tool\t
    🛠️\t7\t0\t锤子与扳手\t工具|扳手|铁锤|锤子\thammer and wrench\thammer|spanner|tool|wrench\t
    🗡️\t7\t0\t匕首\t剑|武器|短刀|短剑\tdagger\tknife|weapon\t
    ⚔️\t7\t0\t交叉放置的剑\t交叉|剑|十字|双剑|战死|武器\tcrossed swords\tcrossed|swords|weapon\t
    💣️\t7\t0\t炸弹\t爆炸\tbomb\tboom|comic|dangerous|explosion|hot\t
    🪃\t7\t0\t回旋镖\t反弹|回弹|土著|武器|飞镖\tboomerang\trebound|repercussion|weapon\t
    🏹\t7\t0\t弓和箭\t人马座|射手|射手座|射箭|弓|弓箭|箭\tbow and arrow\tarcher|archery|arrow|bow|sagittarius|tool|weapon|zodiac\t
    🛡️\t7\t0\t盾牌\t武器|盾|防御\tshield\tweapon\t
    🪚\t7\t0\t木工锯\t修剪|工具|木匠|木材|锯|锯子\tcarpentry saw\tcarpenter|carpentry|cut|lumber|saw|tool|trim\t
    🔧\t7\t0\t扳手\t家居修缮|工具|螺丝扳手\twrench\thome|improvement|spanner|tool\t
    🪛\t7\t0\t螺丝刀\t工具|螺丝\tscrewdriver\tflathead|handy|screw|tool\t
    🔩\t7\t0\t螺母与螺栓\t工具|螺丝|螺帽|螺栓|螺母|螺钉\tnut and bolt\tbolt|home|improvement|nut|tool\t
    ⚙️\t7\t0\t齿轮\t传动|工具|机械|零件\tgear\tcog|cogwheel|tool\t
    🗜️\t7\t0\t夹钳\t压缩|夹具|工具|机械|紧固\tclamp\tcompress|tool|vice\t
    ⚖️\t7\t0\t天平\t公平|公正|天秤|天秤座|星座|正义|法律\tbalance scale\tbalance|justice|libra|scale|scales|tool|weight|zodiac\t
    🦯\t7\t0\t盲杖\t拐杖|无障碍|盲|盲人\twhite cane\taccessibility|blind|cane|probing|white\t
    🔗\t7\t0\t链接\t网址|链条|锁链\tlink\tlinks\t
    ⛓️‍💥\t7\t0\t断链\t手铐|断开|断开的链条|自由|链|链条\tbroken chain\tbreak|breaking|broken|chain|cuffs|freedom\t
    ⛓️\t7\t0\t链条\t铁链|链|锁链\tchains\tchain\t
    🪝\t7\t0\t挂钩\t卖点|弯钩|抓|曲线|钩子|钩状物|鱼钩\thook\tcatch|crook|curve|ensnare|point|selling\t
    🧰\t7\t0\t工具箱\t大箱子|工具|机修|箱子|红盒子\ttoolbox\tbox|chest|mechanic|red|tool\t
    🧲\t7\t0\t磁铁\tu 型|吸引|吸引力|正负|磁性|马蹄铁\tmagnet\tattraction|horseshoe|magnetic|negative|positive|shape|u\t
    🪜\t7\t0\t梯子\t台阶|梯级|横档|爬|爬梯|阶梯\tladder\tclimb|rung|step\t
    🪏\t7\t1\t铲\t埋|挖|掘|洞|种植|花园|锹|雪\tshovel\tbury|dig|garden|hole|plant|scoop|snow|spade\t
    ⚗️\t7\t0\t蒸馏器\t净化|化学|实验|工具|蒸馏\talembic\tchemistry|tool\t
    🧪\t7\t0\t试管\t化学|化学家|实验|实验室|科学\ttest tube\tchemist|chemistry|experiment|lab|science|test|tube\t
    🧫\t7\t0\t培养皿\t培养|实验室|生物学|生物学家|细菌\tpetri dish\tbacteria|biologist|biology|culture|dish|lab|petri\t
    🧬\t7\t0\tDNA\tdna|基因|演化|生命|生物学家|进化|遗传学\tdna\tbiologist|evolution|gene|genetics|life\t
    🔬\t7\t0\t显微镜\t实验|实验室|工具|生物|科学|细胞\tmicroscope\texperiment|lab|science|tool\t
    🔭\t7\t0\t望远镜\t外星人|天体|天文|天文学|工具|接触|科学|观星\ttelescope\tcontact|extraterrestrial|science|tool\t
    📡\t7\t0\t卫星天线\t信号接收|卫星|卫星接收天线|卫星碟形天线|外星人|天线|接触\tsatellite antenna\taliens|antenna|contact|dish|satellite|science\t
    💉\t7\t0\t注射器\t医学|医生|工具|打针|接种|治疗|疫苗|药|针头|针筒\tsyringe\tdoctor|flu|medicine|needle|shot|sick|tool|vaccination\t
    🩸\t7\t0\t血滴\t医疗|月经|流血|献血|经血|输血\tdrop of blood\tbleed|blood|donation|drop|injury|medicine|menstruation\t
    💊\t7\t0\t药丸\t医生|吃药|治疗|生病|用药|维他命|药|药物\tpill\tdoctor|drugs|medicated|medicine|pills|sick|vitamin\t
    🩹\t7\t0\t创可贴\tok绷|伤口|受伤|绷带|胶布\tadhesive bandage\tadhesive|bandage\t
    🩼\t7\t0\t拐杖\t受伤|手杖|残疾|活动助行类辅具|辅助\tcrutch\taid|cane|disability|help|hurt|injured|mobility|stick\t
    🩺\t7\t0\t听诊器\t医生|医疗|心脏|心跳|诊断\tstethoscope\tdoctor|heart|medicine\t
    🩻\t7\t0\tX射线\tx 射线|x射线|医生|医疗|骨架|骨骼\tx-ray\tbones|doctor|medical|skeleton|skull|xray\t
    🚪\t7\t0\t门\t出入口|前门|后门|大门|屋门|房门|房间\tdoor\tback|closet|front\t
    🛗\t7\t0\t电梯\t升降机|可达性\televator\taccessibility|hoist|lift\t
    🪞\t7\t0\t镜子\t化妆|反射|反射镜|窥镜\tmirror\tmakeup|reflection|reflector|speculum\t
    🪟\t7\t0\t窗户\t开窗|新鲜空气|景色|窗口|窗框|透明\twindow\tair|frame|fresh|opening|transparent|view\t
    🛏️\t7\t0\t床\t宾馆|床垫|床铺|睡|睡眠|睡觉\tbed\thotel|sleep\t
    🛋️\t7\t0\t沙发和灯\t家|沙发|灯|阅读\tcouch and lamp\tcouch|hotel|lamp\t
    🪑\t7\t0\t椅子\t坐|坐下|座位|椅背\tchair\tseat|sit\t
    🚽\t7\t0\t马桶\twc|卫生间|厕所|洗手间\ttoilet\tbathroom\t
    🪠\t7\t0\t活塞\t便便|吸力|搋子|水管工|通厕所|马桶\tplunger\tcup|force|plumber|poop|suction|toilet\t
    🚿\t7\t0\t淋浴\t喷头|喷水|水|洗澡 花洒|花洒\tshower\twater\t
    🛁\t7\t0\t浴缸\t沐浴|泡沫浴|泡澡|洗澡|浴盆|澡盆\tbathtub\tbath\t
    🪤\t7\t0\t捕鼠器\t奶酪|老鼠夹|诱饵|陷进|陷阱\tmouse trap\tbait|cheese|lure|mouse|mousetrap|snare|trap\t
    🪒\t7\t0\t剃须刀\t刀|刮|刮刀|剃刀|毛|胡子|锋利\trazor\tsharp|shave\t
    🧴\t7\t0\t乳液瓶\t乳液|保湿乳液|护肤霜|洗剂瓶|洗发水|洗发露|防嗮霜|防晒霜\tlotion bottle\tbottle|lotion|moisturizer|shampoo|sunscreen\t
    🧷\t7\t0\t安全别针\t别针|扣针\tsafety pin\tdiaper|pin|punk|rock|safety\t
    🧹\t7\t0\t扫帚\t女巫|巫婆|打扫|扫地|清洁\tbroom\tcleaning|sweeping|witch\t
    🧺\t7\t0\t筐\t农作|洗衣|种植|篮子|脏衣篮|野餐\tbasket\tfarming|laundry|picnic\t
    🧻\t7\t0\t卷纸\t卫生纸|手纸|纸卷|纸巾\troll of paper\tpaper|roll|toilet|towels\t
    🪣\t7\t0\t桶\t大桶|木桶|水桶|缸\tbucket\tcask|pail|vat\t
    🧼\t7\t0\t皂\t杀菌|泡沫|洗手|洗澡|清洁|肥皂|肥皂泡|肥皂盒|肥皂盘\tsoap\tbar|bathing|clean|cleaning|lather|soapdish\t
    🫧\t7\t0\t气泡\t打嗝|水下|泡泡|清洁|漂浮|珍珠状|肥皂|肥皂泡\tbubbles\tbubble|burp|clean|floating|pearl|soap|underwater\t
    🪥\t7\t0\t牙刷\t刷|刷子|卫生|情节|洗漱|浴室|清洁|牙科|牙齿\ttoothbrush\tbathroom|brush|clean|dental|hygiene|teeth|toiletry\t
    🧽\t7\t0\t海绵\t吸收|吸水|多孔|浸泡|清洁|渗透\tsponge\tabsorbing|cleaning|porous|soak\t
    🧯\t7\t0\t灭火器\t压制|火灾|灭火|熄灭\tfire extinguisher\textinguish|extinguisher|fire|quench\t
    🛒\t7\t0\t购物车\t手推车|购物|采购\tshopping cart\tcart|shopping|trolley\t
    🚬\t7\t0\t香烟\t卷烟|吸烟|抽烟|烟|烟草\tcigarette\tsmoking\t
    ⚰️\t7\t0\t棺材\t埋葬|死亡|灵柩|葬礼|陵墓\tcoffin\tdead|death|vampire\t
    🪦\t7\t0\t墓碑\t公墓|坟墓|墓园|墓地|安息|死亡|纪念\theadstone\tcemetery|dead|grave|graveyard|memorial|rip|tomb|tombstone\t
    ⚱️\t7\t0\t骨灰缸\t丧礼|死亡|瓮|缸|葬礼|骨灰|骨灰罐\tfuneral urn\tashes|death|funeral|urn\t
    🧿\t7\t0\t纳扎尔护身符\t小装饰品|恶魔之眼|护身符|珠子|符咒|纳扎尔|蓝色|邪眼\tnazar amulet\tamulet|bead|blue|charm|evil-eye|nazar|talisman\t
    🪬\t7\t0\t法蒂玛之手\t保护|好运|手|手掌|护身符|法蒂玛|玛丽|米里亚姆\thamsa\tamulet|fatima|fortune|guide|hand|mary|miriam|palm|protect|protection\t
    🗿\t7\t0\t摩埃\t复活岛|复活节岛|复活节岛石像|摩艾|摩艾石像|旅行|毛埃|脸\tmoai\tface|moyai|statue|stoneface|travel\t
    🪧\t7\t0\t标语牌\t告示|布告|标志|标牌|标语|海报|示威|纠察队标语牌|警戒哨\tplacard\tcard|demonstration|notice|picket|plaque|protest|sign\t
    🪪\t7\t0\t身份证\tid|凭证|安全|执照|证件\tidentification card\tcard|credentials|document|id|identification|license|security\t
    🏧\t8\t0\t取款机\tatm|提款机|柜员机|标识|银行\tATM sign\tatm|automated|bank|cash|money|sign|teller\t
    🚮\t8\t0\t倒垃圾\t垃圾丢弃处|垃圾入篓|垃圾桶\tlitter in bin sign\tbin|litter|litterbin|sign\t
    🚰\t8\t0\t饮用水\t可以喝的|喝水|接水|水|水龙头\tpotable water\tdrinking|potable|water\t
    ♿️\t8\t0\t轮椅标识\t无障碍|残疾|残障|轮椅|轮椅符号\twheelchair symbol\taccess|handicap|symbol|wheelchair\t
    🚹️\t8\t0\t男厕\t卫生间|厕所|洗手间|男士\tmen’s room\tbathroom|lavatory|man|men’s|restroom|room|toilet|wc\t
    🚺️\t8\t0\t女厕\t卫生间|厕所|女士|洗手间\twomen’s room\tbathroom|lavatory|restroom|room|toilet|wc|woman|women’s\t
    🚻\t8\t0\t卫生间\twc|厕所|洗手间\trestroom\tbathroom|lavatory|toilet|wc\t
    🚼️\t8\t0\t宝宝\t婴儿|换尿片|母婴室\tbaby symbol\tbaby|changing|symbol\t
    🚾\t8\t0\t厕所\t卫生间|洗手间|盥洗室\twater closet\tbathroom|closet|lavatory|restroom|toilet|water|wc\t
    🛂\t8\t0\t护照检查\t安检|护照|检查|通行证\tpassport control\tcontrol|passport\t
    🛃\t8\t0\t海关\t行李打包\tcustoms\tpacking\t
    🛄\t8\t0\t提取行李\t提取|旅行|行李\tbaggage claim\tarrived|baggage|bags|case|checked|claim|journey|packing|plane|ready|travel|trip\t
    🛅\t8\t0\t寄存行李\t储物柜|寄存|行李\tleft luggage\tbaggage|case|left|locker|luggage\t
    ⚠️\t8\t0\t警告\t小心\twarning\tcaution\t
    🚸\t8\t0\t儿童过街\t交通|安全|指示牌|行人\tchildren crossing\tchild|children|crossing|pedestrian|traffic\t
    ⛔️\t8\t0\t禁止通行\t交通|禁止入内|禁行|请勿入内|请勿驶入\tno entry\tdo|entry|fail|forbidden|no|not|pass|prohibited|traffic\t
    🚫\t8\t0\t禁止\t不准|不许|严禁|禁入|禁行|阻止\tprohibited\tentry|forbidden|no|not|smoke\t
    🚳\t8\t0\t禁止自行车\t严禁|交通|禁止|禁行自行车|自行车|非机动车\tno bicycles\tbicycle|bicycles|bike|forbidden|no|not|prohibited\t
    🚭️\t8\t0\t禁止吸烟\t严禁|吸烟|抽烟|禁止|禁烟\tno smoking\tforbidden|no|not|prohibited|smoke|smoking\t
    🚯\t8\t0\t禁止乱扔垃圾\t严禁|垃圾|禁丢垃圾|禁止\tno littering\tforbidden|litter|littering|no|not|prohibited\t
    🚱\t8\t0\t非饮用水\t水|禁止用水|节约用水|非直饮水\tnon-potable water\tdry|non-drinking|non-potable|prohibited|water\t
    🚷\t8\t0\t禁止行人通行\t严禁|行人\tno pedestrians\tforbidden|no|not|pedestrian|pedestrians|prohibited\t
    📵\t8\t0\t禁止使用手机\t严禁|手机|电话|禁止\tno mobile phones\tcell|forbidden|mobile|no|not|phone|phones|prohibited|telephone\t
    🔞\t8\t0\t18禁\t儿童不宜|未成年人不宜|禁止\tno one under eighteen\t18|age|eighteen|forbidden|no|not|one|prohibited|restriction|underage\t
    ☢️\t8\t0\t辐射\t放射性|标识\tradioactive\tsign\t
    ☣️\t8\t0\t生物危害\t动物|当心感染|污染|警告\tbiohazard\tsign\t
    ⬆️\t8\t0\t向上箭头\t上|北|方位|方向|标识|箭头\tup arrow\tarrow|cardinal|direction|north|up\t
    ↗️\t8\t0\t右上箭头\t东北|右上|方位|方向|标识|箭头\tup-right arrow\tarrow|direction|intercardinal|northeast|up-right\t
    ➡️\t8\t0\t向右箭头\t东|右|方向|标识|箭头\tright arrow\tarrow|cardinal|direction|east|right\t
    ↘️\t8\t0\t右下箭头\t东南|右下|方位|方向|标识|箭头\tdown-right arrow\tarrow|direction|down-right|intercardinal|southeast\t
    ⬇️\t8\t0\t向下箭头\t南|向下|基本|方位|正南|箭头\tdown arrow\tarrow|cardinal|direction|down|south\t
    ↙️\t8\t0\t左下箭头\t左下|方向|标识|箭头|西南\tdown-left arrow\tarrow|direction|down-left|intercardinal|southwest\t
    ⬅️\t8\t0\t向左箭头\t左|方向|标识|箭头|西\tleft arrow\tarrow|cardinal|direction|left|west\t
    ↖️\t8\t0\t左上箭头\t左上|方向|标识|箭头|西北\tup-left arrow\tarrow|direction|intercardinal|northwest|up-left\t
    ↕️\t8\t0\t上下箭头\t上下|箭头\tup-down arrow\tarrow|up-down\t
    ↔️\t8\t0\t左右箭头\t左右|箭头\tleft-right arrow\tarrow|left-right\t
    ↩️\t8\t0\t右转弯箭头\t右转弯|向左弯曲的右箭头|箭头\tright arrow curving left\tarrow|curving|left|right\t
    ↪️\t8\t0\t左转弯箭头\t向右弯曲的左箭头|左转弯|箭头\tleft arrow curving right\tarrow|curving|left|right\t
    ⤴️\t8\t0\t右上弯箭头\t右上弯|向上弯曲的右箭头|箭头\tright arrow curving up\tarrow|curving|right|up\t
    ⤵️\t8\t0\t右下弯箭头\t右下弯|向下弯曲的右箭头|箭头\tright arrow curving down\tarrow|curving|down|right\t
    🔃\t8\t0\t顺时针垂直箭头\t刷新|垂直顺时针箭头|方向|标识|箭头|重新载入|顺时针|顺时针箭头\tclockwise vertical arrows\tarrow|arrows|clockwise|refresh|reload|vertical\t
    🔄\t8\t0\t逆时针箭头按钮\t倒转|再次|刷新|箭头|逆时针|逆时针箭头\tcounterclockwise arrows button\tagain|anticlockwise|arrow|arrows|button|counterclockwise|deja|refresh|rewindershins|vu\t
    🔙\t8\t0\t返回箭头\t回退|箭头|返回\tBACK arrow\tarrow|back\t
    🔚\t8\t0\t结束箭头\t箭头|终点|结束\tEND arrow\tarrow|end\t
    🔛\t8\t0\tON! 箭头\ton|on! 箭头|开始|标识|箭头\tON! arrow\tarrow|mark|on!\t
    🔜\t8\t0\tSOON 箭头\tsoon 箭头|在路上|立刻回来|箭头|马上\tSOON arrow\tarrow|brb|omw|soon\t
    🔝\t8\t0\t置顶\t向上|标识|顶\tTOP arrow\tarrow|homie|top|up\t
    🛐\t8\t0\t宗教场所\t地点|宗教|崇拜|敬神|礼拜|祈祷\tplace of worship\tplace|pray|religion|worship\t
    ⚛️\t8\t0\t原子符号\t原子|无神论|物质\tatom symbol\tatheist|atom|symbol\t
    🕉️\t8\t0\t奥姆\t印度|印度教|唵|宗教\tom\thindu|religion\t
    ✡️\t8\t0\t六芒星\t六角星|大卫之星|大卫星|宗教|犹太|犹太教\tstar of David\tdavid|jew|jewish|judaism|religion|star\t
    ☸️\t8\t0\t法轮\t佛|宗教|舵|轮盘|达摩\twheel of dharma\tbuddhist|dharma|religion|wheel\t
    ☯️\t8\t0\t阴阳\t太极|宗教|道|道教|阳|阴\tyin yang\tdifficult|lives|religion|tao|taoist|total|yang|yin|yinyang\t
    ✝️\t8\t0\t十字架\t基督|天主教|宗教\tlatin cross\tchrist|christian|cross|latin|religion\t
    ☦️\t8\t0\t东正教十字架\t东正教|十字架|基督|宗教|正教会十字\torthodox cross\tchristian|cross|orthodox|religion\t
    ☪️\t8\t0\t星月\t伊斯兰|宗教|斋戒月|穆斯林\tstar and crescent\tcrescent|islam|muslim|ramadan|religion|star\t
    ☮️\t8\t0\t和平符号\t和平\tpeace symbol\thealing|peace|peaceful|symbol\t
    🕎\t8\t0\t烛台\t光明节|宗教|灯台|犹太|犹太教\tmenorah\tcandelabrum|candlestick|hanukkah|jewish|judaism|religion\t
    🔯\t8\t0\t带中间点的六芒星\t六芒星|六芒星加圆点|六角星|命运|犹太|犹太教\tdotted six-pointed star\tdotted|fortune|jewish|judaism|six-pointed|star\t
    🪯\t8\t0\t坎达\t信仰|卡尔萨|善业与佩剑得胜|坎达长剑|宗教|锡克|锡克教|锡克教徒\tkhanda\tdeg|fateh|khalsa|religion|sikh|sikhism|tegh\t
    ♈️\t8\t0\t白羊座\t公羊|星座|牡羊座\tAries\taries|horoscope|ram|zodiac\t
    ♉️\t8\t0\t金牛座\t公牛|星座|金牛\tTaurus\tbull|horoscope|ox|taurus|zodiac\t
    ♊️\t8\t0\t双子座\t双子|孪生子|星座\tGemini\tgemini|horoscope|twins|zodiac\t
    ♋️\t8\t0\t巨蟹座\t巨蟹|星座|螃蟹\tCancer\tcancer|crab|horoscope|zodiac\t
    ♌️\t8\t0\t狮子座\t星座|雄狮\tLeo\thoroscope|leo|lion|zodiac\t
    ♍️\t8\t0\t处女座\t室女座|星座|黄道十二宫\tVirgo\thoroscope|virgo|zodiac\t
    ♎️\t8\t0\t天秤座\t平衡|星座|正义\tLibra\tbalance|horoscope|justice|libra|scales|zodiac\t
    ♏️\t8\t0\t天蝎座\t天蝎|星座|蝎子\tScorpio\thoroscope|scorpio|scorpion|scorpius|zodiac\t
    ♐️\t8\t0\t射手座\t人马座|射手|弓箭手|星座\tSagittarius\tarcher|horoscope|sagittarius|zodiac\t
    ♑️\t8\t0\t摩羯座\t天宫图|山羊|摩羯|星座\tCapricorn\tcapricorn|goat|horoscope|zodiac\t
    ♒️\t8\t0\t水瓶座\t星座|水\tAquarius\taquarius|bearer|horoscope|water|zodiac\t
    ♓️\t8\t0\t双鱼座\t双鱼|星座|鱼\tPisces\tfish|horoscope|pisces|zodiac\t
    ⛎️\t8\t0\t蛇夫座\t星座|蛇|蛇夫\tOphiuchus\tbearer|ophiuchus|serpent|snake|zodiac\t
    🔀\t8\t0\t随机播放音轨按钮\t交叉|打乱|随机|随机播放\tshuffle tracks button\tarrow|button|crossed|shuffle|tracks\t
    🔁\t8\t0\t重复按钮\t循环|循环播放|箭头|顺时针\trepeat button\tarrow|button|clockwise|repeat\t
    🔂\t8\t0\t重复一次按钮\t单曲循环|循环|箭头|顺时针\trepeat single button\tarrow|button|clockwise|once|repeat|single\t
    ▶️\t8\t0\t播放按钮\t三角|右|向右|播放|箭头\tplay button\tarrow|button|play|right|triangle\t
    ⏩️\t8\t0\t快进按钮\t双箭头|向前|快进|快速\tfast-forward button\tarrow|button|double|fast|fast-forward|forward\t
    ⏭️\t8\t0\t下一个音轨按钮\t三角|下一个|下一曲|下一首|往后|箭头\tnext track button\tarrow|button|next|scene|track|triangle\t
    ⏯️\t8\t0\t播放或暂停按钮\t三角|向右|播放|播放或暂停|暂停\tplay or pause button\tarrow|button|pause|play|right|triangle\t
    ◀️\t8\t0\t倒退按钮\t三角|倒转|后退|向左|左\treverse button\tarrow|button|left|reverse|triangle\t
    ⏪️\t8\t0\t快退按钮\t倒回|双箭头|快退|快速倒带\tfast reverse button\tarrow|button|double|fast|reverse|rewind\t
    ⏮️\t8\t0\t上一个音轨按钮\t三角|上一个|上一曲|上一首|箭头\tlast track button\tarrow|button|last|previous|scene|track|triangle\t
    🔼\t8\t0\t向上三角形按钮\t上|向上|向上按钮|往上|箭头\tupwards button\tarrow|button|red|up|upwards\t
    ⏫️\t8\t0\t快速上升按钮\t上|双箭头|向上|快速向上\tfast up button\tarrow|button|double|fast|up\t
    🔽\t8\t0\t向下三角形按钮\t下|向下|向下按钮|往下|箭头\tdownwards button\tarrow|button|down|downwards|red\t
    ⏬️\t8\t0\t快速下降按钮\t下|双箭头|向下|快速向下\tfast down button\tarrow|button|double|down|fast\t
    ⏸️\t8\t0\t暂停按钮\t停止|双条形|暂停\tpause button\tbar|button|double|pause|vertical\t
    ⏹️\t8\t0\t停止按钮\t停止|方形|正方形|终止\tstop button\tbutton|square|stop\t
    ⏺️\t8\t0\t录制按钮\t制作|圆|录像|录制|录音\trecord button\tbutton|circle|record\t
    ⏏️\t8\t0\t推出按钮\t向上三角|弹出\teject button\tbutton|eject\t
    🎦\t8\t0\t电影院\t剧院|场所|影片|摄影机|电影\tcinema\tcamera|film|movie\t
    🔅\t8\t0\t低亮度按钮\t亮度|低|低亮度|昏暗|暗\tdim button\tbrightness|button|dim|low\t
    🔆\t8\t0\t高亮度按钮\t亮|亮度|太阳|明亮|高亮度\tbright button\tbright|brightness|button|light\t
    📶\t8\t0\t信号强度条\t信号|天线|强度|手机|条\tantenna bars\tantenna|bar|bars|cell|communication|mobile|phone|signal|telephone\t
    🛜\t8\t0\t无线\twi-fi|wlan|互联网|宽带|智能手机|热点|电脑|网络|计算机|连接\twireless\tbroadband|computer|connectivity|hotspot|internet|network|router|smartphone|wi-fi|wifi|wlan\t
    📳\t8\t0\t振动模式\t手机|振动|震动\tvibration mode\tcell|communication|mobile|mode|phone|telephone|vibration\t
    📴\t8\t0\t手机关机\t关机|关闭|关闭手机|手机\tmobile phone off\tcell|mobile|off|phone|telephone\t
    ♀️\t8\t0\t女性符号\t符号|雌性\tfemale sign\tfemale|sign|woman\t
    ♂️\t8\t0\t男性符号\t符号|雄性\tmale sign\tmale|man|sign\t
    ⚧️\t8\t0\t跨性别符号\t跨性别\ttransgender symbol\tsymbol|transgender\t
    ✖️\t8\t0\t乘\tx|乘号|取消|相乘|符号\tmultiply\tcancel|multiplication|sign|x|×\t
    ➕️\t8\t0\t加\t加号|十字|数学|相加|符号\tplus\t+\t
    ➖️\t8\t0\t减\t减号|数学|横线|符号\tminus\t-|heavy|math|sign|−\t
    ➗️\t8\t0\t除\t数学|相除|符号|除号\tdivide\tdivision|heavy|math|sign|÷\t
    🟰\t8\t0\t粗等号\t回答|平等|数学|相等|等于|等号|答案\theavy equals sign\tanswer|equal|equality|equals|heavy|math|sign\t
    ♾️\t8\t0\t无穷大\t宇宙|无尽|极大\tinfinity\tforever|unbounded|universal\t
    ‼️\t8\t0\t双感叹号\t两个|双叹号|叹号|吃惊|标点符号|！|！！\tdouble exclamation mark\t!|!!|bangbang|double|exclamation|mark|punctuation\t
    ⁉️\t8\t0\t感叹疑问号\t叹号|叹号加问号|吃惊|标点符号|疑问惊叹号|问号|！|！？|？\texclamation question mark\t!|!?|?|exclamation|interrobang|mark|punctuation|question\t
    ❓️\t8\t0\t红色问号\t为什么|标点|标点符号|疑问|问号\tred question mark\t?|mark|punctuation|question|red\t
    ❔️\t8\t0\t白色问号\t为什么|标点符号|空心|空心问号|问号|问题|？\twhite question mark\t?|mark|outlined|punctuation|question|white\t
    ❕️\t8\t0\t白色感叹号\t叹号|吃惊|标点符号|白色叹号|空心|空心叹号|！\twhite exclamation mark\t!|exclamation|mark|outlined|punctuation|white\t
    ❗️\t8\t0\t红色感叹号\t叹号|吃惊|惊讶|感叹|感叹号|标点符号|！\tred exclamation mark\t!|exclamation|mark|punctuation|red\t
    〰️\t8\t0\t波浪型破折号\t标点符号|波浪线|浪花|象声号\twavy dash\tdash|punctuation|wavy\t
    💱\t8\t0\t货币兑换\t兑换|外汇|换汇|汇率|流通|银行\tcurrency exchange\tbank|currency|exchange|money\t
    💲\t8\t0\t粗美元符号\t现金|美元|美元符号|美刀|货币|金钱\theavy dollar sign\tbillion|cash|charge|currency|dollar|heavy|million|money|pay|sign\t
    ⚕️\t8\t0\t医疗标志\t医学|医疗|蛇杖|阿斯克勒庇俄斯|阿斯克勒庇俄斯蛇杖\tmedical symbol\taesculapius|medical|medicine|staff|symbol\t
    ♻️\t8\t0\t回收标志\t再利用|再生|回收|循环\trecycling symbol\trecycle|recycling|symbol\t
    ⚜️\t8\t0\t百合花饰\t鸢尾花\tfleur-de-lis\tknights\t
    🔱\t8\t0\t三叉戟徽章\t三叉戟|工具|波塞冬|船|锚\ttrident emblem\tanchor|emblem|poseidon|ship|tool|trident\t
    📛\t8\t0\t姓名牌\t名牌|徽章|胸牌|证章\tname badge\tbadge|name\t
    🔰\t8\t0\t日本新手驾驶标志\tv 型臂章|v形图案|人字形图记|军警|叶状|实习|新手|箭尾\tJapanese symbol for beginner\tbeginner|chevron|green|japanese|leaf|symbol|tool|yellow\t
    ⭕️\t8\t0\t红色空心圆圈\t0|o形|圆圈|大|大圆圈|红|零\thollow red circle\tcircle|heavy|hollow|large|o|red\t
    ✅️\t8\t0\t勾号按钮\t勾|勾号|完成|打勾|按钮|绿色打勾\tcheck mark button\tbutton|check|checked|checkmark|complete|completed|done|fixed|mark|tick|✓\t
    ☑️\t8\t0\t勾选框\t做好|勾号|勾选|复选框|带勾方格|打勾|搞定|选票\tcheck box with check\tballot|box|check|checked|done|off|tick|✓\t
    ✔️\t8\t0\t勾号\t对勾|打勾|正确|符号\tcheck mark\tcheck|checked|checkmark|done|heavy|mark|tick|✓\t
    ❌️\t8\t0\t叉号\tx|乘|交叉|取消|相乘|符号\tcross mark\tcancel|cross|mark|multiplication|multiply|x|×\t
    ❎️\t8\t0\t叉号按钮\t乘|乘号|叉|取消|方形\tcross mark button\tbutton|cross|mark|multiplication|multiply|square|x|×\t
    ➰️\t8\t0\t卷曲环\t单环|日本单环标志|标志\tcurly loop\tcurl|curly|loop\t
    ➿️\t8\t0\t双卷曲环\t免费电话|双环|日本免费电话标志|标志\tdouble curly loop\tcurl|curly|double|loop\t
    〽️\t8\t0\t庵点\t开始歌唱|歌记号|符号\tpart alternation mark\talternation|mark|part\t
    ✳️\t8\t0\t八轮辐星号\t八芒星|星号\teight-spoked asterisk\t*|asterisk|eight-spoked\t
    ✴️\t8\t0\t八角星\t星|符号\teight-pointed star\t*|eight-pointed|star\t
    ❇️\t8\t0\t火花\t烟火|闪光|闪耀\tsparkle\t*\t
    ©️\t8\t0\t版权\t版权\tcopyright\tc\t
    ®️\t8\t0\t注册\t注册标记\tregistered\tr\t
    ™️\t8\t0\t商标\t产品|标志\ttrade mark\tmark|tm|trade|trademark\t
    🫟\t8\t1\t泼溅\t喷洒|污渍|油漆|溢出\tsplatter\tdrip|holi|ink|liquid|mess|paint|spill|stain\t
    #️⃣\t8\t0\t按键: #\t按键\tkeycap: #\tkeycap\t
    *️⃣\t8\t0\t按键: *\t按键\tkeycap: *\tkeycap\t
    0️⃣\t8\t0\t按键: 0\t0|按键\tkeycap: 0\t0|keycap|zero\t
    1️⃣\t8\t0\t按键: 1\t1|一|按键\tkeycap: 1\t1|keycap|one\t
    2️⃣\t8\t0\t按键: 2\t2|二|按键\tkeycap: 2\t2|keycap|two\t
    3️⃣\t8\t0\t按键: 3\t3|三|按键\tkeycap: 3\t3|keycap|three\t
    4️⃣\t8\t0\t按键: 4\t4|四|按键\tkeycap: 4\t4|four|keycap\t
    5️⃣\t8\t0\t按键: 5\t5|五|按键\tkeycap: 5\t5|five|keycap\t
    6️⃣\t8\t0\t按键: 6\t6|六|按键\tkeycap: 6\t6|keycap|six\t
    7️⃣\t8\t0\t按键: 7\t7|七|按键\tkeycap: 7\t7|keycap|seven\t
    8️⃣\t8\t0\t按键: 8\t8|八|按键\tkeycap: 8\t8|eight|keycap\t
    9️⃣\t8\t0\t按键: 9\t9|九|按键\tkeycap: 9\t9|keycap|nine\t
    🔟\t8\t0\t按键: 10\t按键\tkeycap: 10\tkeycap\t
    🔠\t8\t0\t输入大写拉丁字母\tabcd|大写字母|大写字母键|字母|打字|拉丁文|输入法\tinput latin uppercase\tabcd|input|latin|letters|uppercase\t
    🔡\t8\t0\t输入小写拉丁字母\tabcd|小写字母|小写字母键|打字|拉丁文|输入小写字母|输入法\tinput latin lowercase\tabcd|input|latin|letters|lowercase\t
    🔢\t8\t0\t输入数字\t1234|打字|数字\tinput numbers\t1234|input|numbers\t
    🔣\t8\t0\t输入符号\t字符|打字|符号\tinput symbols\t%|&|input|symbols|♪|〒\t
    🔤\t8\t0\t输入拉丁字母\tabc|字母|打字|拉丁字母|拉丁字母键|拉丁文|输入字母\tinput latin letters\tabc|alphabet|input|latin|letters\t
    🅰️\t8\t0\tA型血\ta|a型血|字母a|按钮|血型|血液\tA button (blood type)\tblood|button|type\t
    🆎\t8\t0\tAB型血\tab|ab型血|字母ab|按钮|血型|血液\tAB button (blood type)\tab|blood|button|type\t
    🅱️\t8\t0\tB型血\tb|b型血|按钮|血型|血液\tB button (blood type)\tb|blood|button|type\t
    🆑\t8\t0\tCL按钮\tcl|cl按钮|手机|清理|清除\tCL button\tbutton|cl\t
    🆒\t8\t0\tcool按钮\tcool|按键|酷\tCOOL button\tbutton|cool\t
    🆓\t8\t0\t免费按钮\tfree|不收费|免费|按钮|自由\tFREE button\tbutton|free\t
    ℹ️\t8\t0\t信息\t信息中心|查询|资料\tinformation\ti\t
    🆔\t8\t0\tID按钮\tid|id按钮|按键|识别|身份\tID button\tbutton|id|identity\t
    Ⓜ️\t8\t0\t圆圈包围的M\tm|圆圈包围的m|圈|字母|米\tcircled M\tcircle|circled|m\t
    🆕\t8\t0\tnew按钮\t按键|新|新的\tNEW button\tbutton|new\t
    🆖\t8\t0\tNG按钮\tng|ng按钮|按钮|按键|花絮\tNG button\tbutton|ng\t
    🅾️\t8\t0\tO 型血\to|o 型血|o型血|字母o|按钮|血型|血液\tO button (blood type)\tblood|button|o|type\t
    🆗\t8\t0\tOK按钮\tok|ok按钮|同意|按键\tOK button\tbutton|ok|okay\t
    🅿️\t8\t0\t停车按钮\tp|停车|按键|泊车\tP button\tbutton|p|parking\t
    🆘\t8\t0\tSOS按钮\tsos|sos按钮|按键|救命|求救|求救钮\tSOS button\tbutton|help|sos\t
    🆙\t8\t0\tup按钮\tup|向上|按键\tUP! button\tbutton|mark|up|up!\t
    🆚\t8\t0\tVS按钮\tvs|vs按钮|对|对决|按键\tVS button\tbutton|versus|vs\t
    🈁\t8\t0\t日文的“这里”按钮\tkoko|按键|日文|日语|此处|片假名|这里\tJapanese “here” button\tbutton|here|japanese|katakana\t
    🈂️\t8\t0\t日文的“服务费”按钮\tsa|按键|收费|日文|日文sa|日语|服务|服务费|片假名\tJapanese “service charge” button\tbutton|charge|japanese|katakana|service\t
    🈷️\t8\t0\t日文的“月总量”按钮\t按键|日文|日本|月|月度|统计|表意文字\tJapanese “monthly amount” button\tamount|button|ideograph|japanese|monthly\t
    🈶\t8\t0\t日文的“收费”按钮\t按键|日文|日本|有|有料|表意文字|要收费|费用\tJapanese “not free of charge” button\tbutton|charge|free|ideograph|japanese|not\t
    🈯️\t8\t0\t日文的“预留”按钮\t保留|指|按键|日文|日本|表意文字|预定|预订\tJapanese “reserved” button\tbutton|ideograph|japanese|reserved\t
    🉐\t8\t0\t日文的“议价”按钮\t得|按键|日文|日本|表意文字|讨价还价\tJapanese “bargain” button\tbargain|button|ideograph|japanese\t
    🈹\t8\t0\t日文的“打折”按钮\t割|打折|折扣|按键|日文|日本|表意文字\tJapanese “discount” button\tbutton|discount|ideograph|japanese\t
    🈚️\t8\t0\t日文的“免费”按钮\t免费|免钱|按键|无|日文|日本|表意文字\tJapanese “free of charge” button\tbutton|charge|free|ideograph|japanese\t
    🈲\t8\t0\t日文的“禁止”按钮\t严禁|按键|日文|日本|禁|表意文字\tJapanese “prohibited” button\tbutton|ideograph|japanese|prohibited\t
    🉑\t8\t0\t日文的“可接受”按钮\t可|可接受|按键|日文|日本|表意文字|许可\tJapanese “acceptable” button\tacceptable|button|ideograph|japanese\t
    🈸\t8\t0\t日文的“申请”按钮\t日文|日本|日语|申|申请|申请书|申请表|表意文字\tJapanese “application” button\tapplication|button|ideograph|japanese\t
    🈴\t8\t0\t日文的“合格”按钮\t及格|合|按键|日文|日本|表意文字|过关|通过\tJapanese “passing grade” button\tbutton|grade|ideograph|japanese|passing\t
    🈳\t8\t0\t日文的“有空位”按钮\t日文|日本|日语|有空位|空|空位|空闲|表意文字\tJapanese “vacancy” button\tbutton|ideograph|japanese|vacancy\t
    ㊗️\t8\t0\t日文的“祝贺”按钮\t庆贺|按键|日文|日本|祝|祝福|祝贺|表意文字\tJapanese “congratulations” button\tbutton|congratulations|ideograph|japanese\t
    ㊙️\t8\t0\t日文的“秘密”按钮\t保密|按键|日文|日本|秘|秘密|表意文字\tJapanese “secret” button\tbutton|ideograph|japanese|secret\t
    🈺\t8\t0\t日文的“开始营业”按钮\t开门|按键|日文|日本|营|营业|营业中|表意文字\tJapanese “open for business” button\tbusiness|button|ideograph|japanese|open\t
    🈵\t8\t0\t日文的“没有空位”按钮\t座位|按键|日文|日本|满|表意文字\tJapanese “no vacancy” button\tbutton|ideograph|japanese|no|vacancy\t
    🔴\t8\t0\t红色圆\t几何|圆|圈|红|红圈|红色\tred circle\tcircle|geometric|red\t
    🟠\t8\t0\t橙色圆\t圆|圆圈|圈|橙\torange circle\tcircle|orange\t
    🟡\t8\t0\t黄色圆\t圆|圈|黄|黄色|黄色圆圈\tyellow circle\tcircle|yellow\t
    🟢\t8\t0\t绿色圆\t圆|圆圈|圈|绿\tgreen circle\tcircle|green\t
    🔵\t8\t0\t蓝色圆\t圆|圈|蓝|蓝圈\tblue circle\tblue|circle|geometric\t
    🟣\t8\t0\t紫色圆\t圆|圆圈|圈|紫|紫色|紫色圆圈\tpurple circle\tcircle|purple\t
    🟤\t8\t0\t棕色圆\t圆|圆圈|圈|棕\tbrown circle\tbrown|circle\t
    ⚫️\t8\t0\t黑色圆\t圆|圈|黑\tblack circle\tblack|circle|geometric\t
    ⚪️\t8\t0\t白色圆\t圆|圈|白|白圈\twhite circle\tcircle|geometric|white\t
    🟥\t8\t0\t红色方块\t方块|方框|正方形|红|红色\tred square\tcard|penalty|red|square\t
    🟧\t8\t0\t橙色方块\t方块|方框|橙|橙色|正方形\torange square\torange|square\t
    🟨\t8\t0\t黄色方块\t方块|方框|正方形|黄|黄色\tyellow square\tcard|penalty|square|yellow\t
    🟩\t8\t0\t绿色方块\t方块|方框|正方形|绿|绿色\tgreen square\tgreen|square\t
    🟦\t8\t0\t蓝色方块\t方块|方框|正方形|蓝|蓝色\tblue square\tblue|square\t
    🟪\t8\t0\t紫色方块\t方块|方框|正方形|紫|紫色\tpurple square\tpurple|square\t
    🟫\t8\t0\t棕色方块\t方块|方框|棕|棕色|正方形\tbrown square\tbrown|square\t
    ⬛️\t8\t0\t黑线大方框\t大|方形|正方形|黑色|黑色大方形\tblack large square\tblack|geometric|large|square\t
    ⬜️\t8\t0\t白线大方框\t大|方形|正方形|白色|白色方块\twhite large square\tgeometric|large|square|white\t
    ◼️\t8\t0\t黑色中方块\t中等|几何|方形|正方形|黑色\tblack medium square\tblack|geometric|medium|square\t
    ◻️\t8\t0\t白色中方块\t中等|方形|正方形|白色\twhite medium square\tgeometric|medium|square|white\t
    ◾️\t8\t0\t黑色中小方块\t中小|方形|正方形|黑色\tblack medium-small square\tblack|geometric|medium-small|square\t
    ◽️\t8\t0\t白色中小方块\t中小 正方形|几何|方形|白色\twhite medium-small square\tgeometric|medium-small|square|white\t
    ▪️\t8\t0\t黑色小方块\t几何|几何图形|小|方形|正方形|黑色\tblack small square\tblack|geometric|small|square\t
    ▫️\t8\t0\t白色小方块\t小|方形|正方形|白色\twhite small square\tgeometric|small|square|white\t
    🔶\t8\t0\t橙色大菱形\t大|方块|方片|橘色方块|橘黄色|橙色方块|菱形|钻石\tlarge orange diamond\tdiamond|geometric|large|orange\t
    🔷\t8\t0\t蓝色大菱形\t大|方块|方片|菱形|蓝色|钻石\tlarge blue diamond\tblue|diamond|geometric|large\t
    🔸\t8\t0\t橙色小菱形\t小|方块|方片|橘色方块|橘黄色|菱形\tsmall orange diamond\tdiamond|geometric|orange|small\t
    🔹\t8\t0\t蓝色小菱形\t小|方片|菱形|蓝色|蓝色方块|钻石\tsmall blue diamond\tblue|diamond|geometric|small\t
    🔺\t8\t0\t红色正三角\t三角形|向上|正三角|红色\tred triangle pointed up\tgeometric|pointed|red|triangle|up\t
    🔻\t8\t0\t红色倒三角\t三角形|下|倒三角|向下|红色\tred triangle pointed down\tdown|geometric|pointed|red|triangle\t
    💠\t8\t0\t带圆点的菱形\t中心|内部|圆|方块|方块内有点|梅花形|菱形\tdiamond with a dot\tcomic|diamond|dot|geometric\t
    🔘\t8\t0\t单选按钮\t单独|单选钮|圆心|按钮|按键|选中\tradio button\tbutton|geometric|radio\t
    🔳\t8\t0\t白色方形按钮\t按钮|方形|白线方形按钮|白线正方形按钮|白色正方形按钮|白边线方形按钮|白边线正方形按钮\twhite square button\tbutton|geometric|outlined|square|white\t
    🔲\t8\t0\t黑色方形按钮\t几何|几何图形|按钮|方形|黑线方形按钮|黑线正方形按钮|黑色正方形按钮|黑边线方形按钮|黑边线正方形按钮\tblack square button\tblack|button|geometric|square\t
    🏁\t9\t0\t黑白方格旗\t方格|格子旗|竞赛|终点|终点旗|黑白方格\tchequered flag\tcheckered|chequered|finish|flag|flags|game|race|racing|sport|win\t
    🚩\t9\t0\t三角旗\t升旗|旗|旗杆上的三角旗|旗杆上的旗帜|红色旗帜|高尔夫\ttriangular flag\tconstruction|flag|golf|post|triangular\t
    🎌\t9\t0\t交叉旗\t对叉|旗|旗帜|日本\tcrossed flags\tcelebration|cross|crossed|flags|japanese\t
    🏴\t9\t0\t黑旗\t举黑旗|摇黑棋|黑色旗|黑色旗子|黑色旗帜\tblack flag\tblack|flag|waving\t
    🏳️\t9\t0\t白旗\t举白旗|摇白旗|白色旗子|白色旗帜\twhite flag\tflag|waving|white\t
    🏳️‍🌈\t9\t0\t彩虹旗\t双性|同性|多色|彩虹|旗|旗帜|跨性别\trainbow flag\tbisexual|flag|gay|genderqueer|glbt|glbtq|lesbian|lgbt|lgbtq|lgbtqia|pride|queer|rainbow|trans|transgender\t
    🏳️‍⚧️\t9\t0\t跨性别旗\t旗帜|浅蓝色|白色|粉红色|跨性别\ttransgender flag\tblue|flag|light|pink|transgender|white\t
    🏴‍☠️\t9\t0\t海盗旗\t掠夺|海上|财宝|骷髅\tpirate flag\tflag|jolly|pirate|plunder|roger|treasure\t
    🇦🇨\t9\t0\t旗: 阿森松岛\tAC|旗\tflag: Ascension Island\tAC|flag\t
    🇦🇩\t9\t0\t旗: 安道尔\tAD|旗\tflag: Andorra\tAD|flag\t
    🇦🇪\t9\t0\t旗: 阿拉伯联合酋长国\tAE|旗\tflag: United Arab Emirates\tAE|flag\t
    🇦🇫\t9\t0\t旗: 阿富汗\tAF|旗\tflag: Afghanistan\tAF|flag\t
    🇦🇬\t9\t0\t旗: 安提瓜和巴布达\tAG|旗\tflag: Antigua & Barbuda\tAG|flag\t
    🇦🇮\t9\t0\t旗: 安圭拉\tAI|旗\tflag: Anguilla\tAI|flag\t
    🇦🇱\t9\t0\t旗: 阿尔巴尼亚\tAL|旗\tflag: Albania\tAL|flag\t
    🇦🇲\t9\t0\t旗: 亚美尼亚\tAM|旗\tflag: Armenia\tAM|flag\t
    🇦🇴\t9\t0\t旗: 安哥拉\tAO|旗\tflag: Angola\tAO|flag\t
    🇦🇶\t9\t0\t旗: 南极洲\tAQ|旗\tflag: Antarctica\tAQ|flag\t
    🇦🇷\t9\t0\t旗: 阿根廷\tAR|旗\tflag: Argentina\tAR|flag\t
    🇦🇸\t9\t0\t旗: 美属萨摩亚\tAS|旗\tflag: American Samoa\tAS|flag\t
    🇦🇹\t9\t0\t旗: 奥地利\tAT|旗\tflag: Austria\tAT|flag\t
    🇦🇺\t9\t0\t旗: 澳大利亚\tAU|旗\tflag: Australia\tAU|flag\t
    🇦🇼\t9\t0\t旗: 阿鲁巴\tAW|旗\tflag: Aruba\tAW|flag\t
    🇦🇽\t9\t0\t旗: 奥兰群岛\tAX|旗\tflag: Åland Islands\tAX|flag\t
    🇦🇿\t9\t0\t旗: 阿塞拜疆\tAZ|旗\tflag: Azerbaijan\tAZ|flag\t
    🇧🇦\t9\t0\t旗: 波斯尼亚和黑塞哥维那\tBA|旗\tflag: Bosnia & Herzegovina\tBA|flag\t
    🇧🇧\t9\t0\t旗: 巴巴多斯\tBB|旗\tflag: Barbados\tBB|flag\t
    🇧🇩\t9\t0\t旗: 孟加拉国\tBD|旗\tflag: Bangladesh\tBD|flag\t
    🇧🇪\t9\t0\t旗: 比利时\tBE|旗\tflag: Belgium\tBE|flag\t
    🇧🇫\t9\t0\t旗: 布基纳法索\tBF|旗\tflag: Burkina Faso\tBF|flag\t
    🇧🇬\t9\t0\t旗: 保加利亚\tBG|旗\tflag: Bulgaria\tBG|flag\t
    🇧🇭\t9\t0\t旗: 巴林\tBH|旗\tflag: Bahrain\tBH|flag\t
    🇧🇮\t9\t0\t旗: 布隆迪\tBI|旗\tflag: Burundi\tBI|flag\t
    🇧🇯\t9\t0\t旗: 贝宁\tBJ|旗\tflag: Benin\tBJ|flag\t
    🇧🇱\t9\t0\t旗: 圣巴泰勒米\tBL|旗\tflag: St. Barthélemy\tBL|flag\t
    🇧🇲\t9\t0\t旗: 百慕大\tBM|旗\tflag: Bermuda\tBM|flag\t
    🇧🇳\t9\t0\t旗: 文莱\tBN|旗\tflag: Brunei\tBN|flag\t
    🇧🇴\t9\t0\t旗: 玻利维亚\tBO|旗\tflag: Bolivia\tBO|flag\t
    🇧🇶\t9\t0\t旗: 荷属加勒比区\tBQ|旗\tflag: Caribbean Netherlands\tBQ|flag\t
    🇧🇷\t9\t0\t旗: 巴西\tBR|旗\tflag: Brazil\tBR|flag\t
    🇧🇸\t9\t0\t旗: 巴哈马\tBS|旗\tflag: Bahamas\tBS|flag\t
    🇧🇹\t9\t0\t旗: 不丹\tBT|旗\tflag: Bhutan\tBT|flag\t
    🇧🇻\t9\t0\t旗: 布韦岛\tBV|旗\tflag: Bouvet Island\tBV|flag\t
    🇧🇼\t9\t0\t旗: 博茨瓦纳\tBW|旗\tflag: Botswana\tBW|flag\t
    🇧🇾\t9\t0\t旗: 白俄罗斯\tBY|旗\tflag: Belarus\tBY|flag\t
    🇧🇿\t9\t0\t旗: 伯利兹\tBZ|旗\tflag: Belize\tBZ|flag\t
    🇨🇦\t9\t0\t旗: 加拿大\tCA|旗\tflag: Canada\tCA|flag\t
    🇨🇨\t9\t0\t旗: 科科斯（基林）群岛\tCC|旗\tflag: Cocos (Keeling) Islands\tCC|flag\t
    🇨🇩\t9\t0\t旗: 刚果（金）\tCD|旗\tflag: Congo - Kinshasa\tCD|flag\t
    🇨🇫\t9\t0\t旗: 中非共和国\tCF|旗\tflag: Central African Republic\tCF|flag\t
    🇨🇬\t9\t0\t旗: 刚果（布）\tCG|旗\tflag: Congo - Brazzaville\tCG|flag\t
    🇨🇭\t9\t0\t旗: 瑞士\tCH|旗\tflag: Switzerland\tCH|flag\t
    🇨🇮\t9\t0\t旗: 科特迪瓦\tCI|旗\tflag: Côte d’Ivoire\tCI|flag\t
    🇨🇰\t9\t0\t旗: 库克群岛\tCK|旗\tflag: Cook Islands\tCK|flag\t
    🇨🇱\t9\t0\t旗: 智利\tCL|旗\tflag: Chile\tCL|flag\t
    🇨🇲\t9\t0\t旗: 喀麦隆\tCM|旗\tflag: Cameroon\tCM|flag\t
    🇨🇳\t9\t0\t旗: 中国\tCN|旗\tflag: China\tCN|flag\t
    🇨🇴\t9\t0\t旗: 哥伦比亚\tCO|旗\tflag: Colombia\tCO|flag\t
    🇨🇵\t9\t0\t旗: 克利珀顿岛\tCP|旗\tflag: Clipperton Island\tCP|flag\t
    🇨🇶\t9\t1\t旗: 萨克岛\tCQ|旗\tflag: Sark\tCQ|flag\t
    🇨🇷\t9\t0\t旗: 哥斯达黎加\tCR|旗\tflag: Costa Rica\tCR|flag\t
    🇨🇺\t9\t0\t旗: 古巴\tCU|旗\tflag: Cuba\tCU|flag\t
    🇨🇻\t9\t0\t旗: 佛得角\tCV|旗\tflag: Cape Verde\tCV|flag\t
    🇨🇼\t9\t0\t旗: 库拉索\tCW|旗\tflag: Curaçao\tCW|flag\t
    🇨🇽\t9\t0\t旗: 圣诞岛\tCX|旗\tflag: Christmas Island\tCX|flag\t
    🇨🇾\t9\t0\t旗: 塞浦路斯\tCY|旗\tflag: Cyprus\tCY|flag\t
    🇨🇿\t9\t0\t旗: 捷克\tCZ|旗\tflag: Czechia\tCZ|flag\t
    🇩🇪\t9\t0\t旗: 德国\tDE|旗\tflag: Germany\tDE|flag\t
    🇩🇬\t9\t0\t旗: 迪戈加西亚岛\tDG|旗\tflag: Diego Garcia\tDG|flag\t
    🇩🇯\t9\t0\t旗: 吉布提\tDJ|旗\tflag: Djibouti\tDJ|flag\t
    🇩🇰\t9\t0\t旗: 丹麦\tDK|旗\tflag: Denmark\tDK|flag\t
    🇩🇲\t9\t0\t旗: 多米尼克\tDM|旗\tflag: Dominica\tDM|flag\t
    🇩🇴\t9\t0\t旗: 多米尼加共和国\tDO|旗\tflag: Dominican Republic\tDO|flag\t
    🇩🇿\t9\t0\t旗: 阿尔及利亚\tDZ|旗\tflag: Algeria\tDZ|flag\t
    🇪🇦\t9\t0\t旗: 休达及梅利利亚\tEA|旗\tflag: Ceuta & Melilla\tEA|flag\t
    🇪🇨\t9\t0\t旗: 厄瓜多尔\tEC|旗\tflag: Ecuador\tEC|flag\t
    🇪🇪\t9\t0\t旗: 爱沙尼亚\tEE|旗\tflag: Estonia\tEE|flag\t
    🇪🇬\t9\t0\t旗: 埃及\tEG|旗\tflag: Egypt\tEG|flag\t
    🇪🇭\t9\t0\t旗: 西撒哈拉\tEH|旗\tflag: Western Sahara\tEH|flag\t
    🇪🇷\t9\t0\t旗: 厄立特里亚\tER|旗\tflag: Eritrea\tER|flag\t
    🇪🇸\t9\t0\t旗: 西班牙\tES|旗\tflag: Spain\tES|flag\t
    🇪🇹\t9\t0\t旗: 埃塞俄比亚\tET|旗\tflag: Ethiopia\tET|flag\t
    🇪🇺\t9\t0\t旗: 欧盟\tEU|旗\tflag: European Union\tEU|flag\t
    🇫🇮\t9\t0\t旗: 芬兰\tFI|旗\tflag: Finland\tFI|flag\t
    🇫🇯\t9\t0\t旗: 斐济\tFJ|旗\tflag: Fiji\tFJ|flag\t
    🇫🇰\t9\t0\t旗: 福克兰群岛\tFK|旗\tflag: Falkland Islands\tFK|flag\t
    🇫🇲\t9\t0\t旗: 密克罗尼西亚\tFM|旗\tflag: Micronesia\tFM|flag\t
    🇫🇴\t9\t0\t旗: 法罗群岛\tFO|旗\tflag: Faroe Islands\tFO|flag\t
    🇫🇷\t9\t0\t旗: 法国\tFR|旗\tflag: France\tFR|flag\t
    🇬🇦\t9\t0\t旗: 加蓬\tGA|旗\tflag: Gabon\tGA|flag\t
    🇬🇧\t9\t0\t旗: 英国\tGB|旗\tflag: United Kingdom\tGB|flag\t
    🇬🇩\t9\t0\t旗: 格林纳达\tGD|旗\tflag: Grenada\tGD|flag\t
    🇬🇪\t9\t0\t旗: 格鲁吉亚\tGE|旗\tflag: Georgia\tGE|flag\t
    🇬🇫\t9\t0\t旗: 法属圭亚那\tGF|旗\tflag: French Guiana\tGF|flag\t
    🇬🇬\t9\t0\t旗: 根西岛\tGG|旗\tflag: Guernsey\tGG|flag\t
    🇬🇭\t9\t0\t旗: 加纳\tGH|旗\tflag: Ghana\tGH|flag\t
    🇬🇮\t9\t0\t旗: 直布罗陀\tGI|旗\tflag: Gibraltar\tGI|flag\t
    🇬🇱\t9\t0\t旗: 格陵兰\tGL|旗\tflag: Greenland\tGL|flag\t
    🇬🇲\t9\t0\t旗: 冈比亚\tGM|旗\tflag: Gambia\tGM|flag\t
    🇬🇳\t9\t0\t旗: 几内亚\tGN|旗\tflag: Guinea\tGN|flag\t
    🇬🇵\t9\t0\t旗: 瓜德罗普\tGP|旗\tflag: Guadeloupe\tGP|flag\t
    🇬🇶\t9\t0\t旗: 赤道几内亚\tGQ|旗\tflag: Equatorial Guinea\tGQ|flag\t
    🇬🇷\t9\t0\t旗: 希腊\tGR|旗\tflag: Greece\tGR|flag\t
    🇬🇸\t9\t0\t旗: 南乔治亚和南桑威奇群岛\tGS|旗\tflag: South Georgia & South Sandwich Islands\tGS|flag\t
    🇬🇹\t9\t0\t旗: 危地马拉\tGT|旗\tflag: Guatemala\tGT|flag\t
    🇬🇺\t9\t0\t旗: 关岛\tGU|旗\tflag: Guam\tGU|flag\t
    🇬🇼\t9\t0\t旗: 几内亚比绍\tGW|旗\tflag: Guinea-Bissau\tGW|flag\t
    🇬🇾\t9\t0\t旗: 圭亚那\tGY|旗\tflag: Guyana\tGY|flag\t
    🇭🇰\t9\t0\t旗: 中国香港特别行政区\tHK|旗\tflag: Hong Kong SAR China\tHK|flag\t
    🇭🇲\t9\t0\t旗: 赫德岛和麦克唐纳群岛\tHM|旗\tflag: Heard & McDonald Islands\tHM|flag\t
    🇭🇳\t9\t0\t旗: 洪都拉斯\tHN|旗\tflag: Honduras\tHN|flag\t
    🇭🇷\t9\t0\t旗: 克罗地亚\tHR|旗\tflag: Croatia\tHR|flag\t
    🇭🇹\t9\t0\t旗: 海地\tHT|旗\tflag: Haiti\tHT|flag\t
    🇭🇺\t9\t0\t旗: 匈牙利\tHU|旗\tflag: Hungary\tHU|flag\t
    🇮🇨\t9\t0\t旗: 加纳利群岛\tIC|旗\tflag: Canary Islands\tIC|flag\t
    🇮🇩\t9\t0\t旗: 印度尼西亚\tID|旗\tflag: Indonesia\tID|flag\t
    🇮🇪\t9\t0\t旗: 爱尔兰\tIE|旗\tflag: Ireland\tIE|flag\t
    🇮🇱\t9\t0\t旗: 以色列\tIL|旗\tflag: Israel\tIL|flag\t
    🇮🇲\t9\t0\t旗: 马恩岛\tIM|旗\tflag: Isle of Man\tIM|flag\t
    🇮🇳\t9\t0\t旗: 印度\tIN|旗\tflag: India\tIN|flag\t
    🇮🇴\t9\t0\t旗: 英属印度洋领地\tIO|旗\tflag: British Indian Ocean Territory\tIO|flag\t
    🇮🇶\t9\t0\t旗: 伊拉克\tIQ|旗\tflag: Iraq\tIQ|flag\t
    🇮🇷\t9\t0\t旗: 伊朗\tIR|旗\tflag: Iran\tIR|flag\t
    🇮🇸\t9\t0\t旗: 冰岛\tIS|旗\tflag: Iceland\tIS|flag\t
    🇮🇹\t9\t0\t旗: 意大利\tIT|旗\tflag: Italy\tIT|flag\t
    🇯🇪\t9\t0\t旗: 泽西岛\tJE|旗\tflag: Jersey\tJE|flag\t
    🇯🇲\t9\t0\t旗: 牙买加\tJM|旗\tflag: Jamaica\tJM|flag\t
    🇯🇴\t9\t0\t旗: 约旦\tJO|旗\tflag: Jordan\tJO|flag\t
    🇯🇵\t9\t0\t旗: 日本\tJP|旗\tflag: Japan\tJP|flag\t
    🇰🇪\t9\t0\t旗: 肯尼亚\tKE|旗\tflag: Kenya\tKE|flag\t
    🇰🇬\t9\t0\t旗: 吉尔吉斯斯坦\tKG|旗\tflag: Kyrgyzstan\tKG|flag\t
    🇰🇭\t9\t0\t旗: 柬埔寨\tKH|旗\tflag: Cambodia\tKH|flag\t
    🇰🇮\t9\t0\t旗: 基里巴斯\tKI|旗\tflag: Kiribati\tKI|flag\t
    🇰🇲\t9\t0\t旗: 科摩罗\tKM|旗\tflag: Comoros\tKM|flag\t
    🇰🇳\t9\t0\t旗: 圣基茨和尼维斯\tKN|旗\tflag: St. Kitts & Nevis\tKN|flag\t
    🇰🇵\t9\t0\t旗: 朝鲜\tKP|旗\tflag: North Korea\tKP|flag\t
    🇰🇷\t9\t0\t旗: 韩国\tKR|旗\tflag: South Korea\tKR|flag\t
    🇰🇼\t9\t0\t旗: 科威特\tKW|旗\tflag: Kuwait\tKW|flag\t
    🇰🇾\t9\t0\t旗: 开曼群岛\tKY|旗\tflag: Cayman Islands\tKY|flag\t
    🇰🇿\t9\t0\t旗: 哈萨克斯坦\tKZ|旗\tflag: Kazakhstan\tKZ|flag\t
    🇱🇦\t9\t0\t旗: 老挝\tLA|旗\tflag: Laos\tLA|flag\t
    🇱🇧\t9\t0\t旗: 黎巴嫩\tLB|旗\tflag: Lebanon\tLB|flag\t
    🇱🇨\t9\t0\t旗: 圣卢西亚\tLC|旗\tflag: St. Lucia\tLC|flag\t
    🇱🇮\t9\t0\t旗: 列支敦士登\tLI|旗\tflag: Liechtenstein\tLI|flag\t
    🇱🇰\t9\t0\t旗: 斯里兰卡\tLK|旗\tflag: Sri Lanka\tLK|flag\t
    🇱🇷\t9\t0\t旗: 利比里亚\tLR|旗\tflag: Liberia\tLR|flag\t
    🇱🇸\t9\t0\t旗: 莱索托\tLS|旗\tflag: Lesotho\tLS|flag\t
    🇱🇹\t9\t0\t旗: 立陶宛\tLT|旗\tflag: Lithuania\tLT|flag\t
    🇱🇺\t9\t0\t旗: 卢森堡\tLU|旗\tflag: Luxembourg\tLU|flag\t
    🇱🇻\t9\t0\t旗: 拉脱维亚\tLV|旗\tflag: Latvia\tLV|flag\t
    🇱🇾\t9\t0\t旗: 利比亚\tLY|旗\tflag: Libya\tLY|flag\t
    🇲🇦\t9\t0\t旗: 摩洛哥\tMA|旗\tflag: Morocco\tMA|flag\t
    🇲🇨\t9\t0\t旗: 摩纳哥\tMC|旗\tflag: Monaco\tMC|flag\t
    🇲🇩\t9\t0\t旗: 摩尔多瓦\tMD|旗\tflag: Moldova\tMD|flag\t
    🇲🇪\t9\t0\t旗: 黑山\tME|旗\tflag: Montenegro\tME|flag\t
    🇲🇫\t9\t0\t旗: 法属圣马丁\tMF|旗\tflag: St. Martin\tMF|flag\t
    🇲🇬\t9\t0\t旗: 马达加斯加\tMG|旗\tflag: Madagascar\tMG|flag\t
    🇲🇭\t9\t0\t旗: 马绍尔群岛\tMH|旗\tflag: Marshall Islands\tMH|flag\t
    🇲🇰\t9\t0\t旗: 北马其顿\tMK|旗\tflag: North Macedonia\tMK|flag\t
    🇲🇱\t9\t0\t旗: 马里\tML|旗\tflag: Mali\tML|flag\t
    🇲🇲\t9\t0\t旗: 缅甸\tMM|旗\tflag: Myanmar (Burma)\tMM|flag\t
    🇲🇳\t9\t0\t旗: 蒙古\tMN|旗\tflag: Mongolia\tMN|flag\t
    🇲🇴\t9\t0\t旗: 中国澳门特别行政区\tMO|旗\tflag: Macao SAR China\tMO|flag\t
    🇲🇵\t9\t0\t旗: 北马里亚纳群岛\tMP|旗\tflag: Northern Mariana Islands\tMP|flag\t
    🇲🇶\t9\t0\t旗: 马提尼克\tMQ|旗\tflag: Martinique\tMQ|flag\t
    🇲🇷\t9\t0\t旗: 毛里塔尼亚\tMR|旗\tflag: Mauritania\tMR|flag\t
    🇲🇸\t9\t0\t旗: 蒙特塞拉特\tMS|旗\tflag: Montserrat\tMS|flag\t
    🇲🇹\t9\t0\t旗: 马耳他\tMT|旗\tflag: Malta\tMT|flag\t
    🇲🇺\t9\t0\t旗: 毛里求斯\tMU|旗\tflag: Mauritius\tMU|flag\t
    🇲🇻\t9\t0\t旗: 马尔代夫\tMV|旗\tflag: Maldives\tMV|flag\t
    🇲🇼\t9\t0\t旗: 马拉维\tMW|旗\tflag: Malawi\tMW|flag\t
    🇲🇽\t9\t0\t旗: 墨西哥\tMX|旗\tflag: Mexico\tMX|flag\t
    🇲🇾\t9\t0\t旗: 马来西亚\tMY|旗\tflag: Malaysia\tMY|flag\t
    🇲🇿\t9\t0\t旗: 莫桑比克\tMZ|旗\tflag: Mozambique\tMZ|flag\t
    🇳🇦\t9\t0\t旗: 纳米比亚\tNA|旗\tflag: Namibia\tNA|flag\t
    🇳🇨\t9\t0\t旗: 新喀里多尼亚\tNC|旗\tflag: New Caledonia\tNC|flag\t
    🇳🇪\t9\t0\t旗: 尼日尔\tNE|旗\tflag: Niger\tNE|flag\t
    🇳🇫\t9\t0\t旗: 诺福克岛\tNF|旗\tflag: Norfolk Island\tNF|flag\t
    🇳🇬\t9\t0\t旗: 尼日利亚\tNG|旗\tflag: Nigeria\tNG|flag\t
    🇳🇮\t9\t0\t旗: 尼加拉瓜\tNI|旗\tflag: Nicaragua\tNI|flag\t
    🇳🇱\t9\t0\t旗: 荷兰\tNL|旗\tflag: Netherlands\tNL|flag\t
    🇳🇴\t9\t0\t旗: 挪威\tNO|旗\tflag: Norway\tNO|flag\t
    🇳🇵\t9\t0\t旗: 尼泊尔\tNP|旗\tflag: Nepal\tNP|flag\t
    🇳🇷\t9\t0\t旗: 瑙鲁\tNR|旗\tflag: Nauru\tNR|flag\t
    🇳🇺\t9\t0\t旗: 纽埃\tNU|旗\tflag: Niue\tNU|flag\t
    🇳🇿\t9\t0\t旗: 新西兰\tNZ|旗\tflag: New Zealand\tNZ|flag\t
    🇴🇲\t9\t0\t旗: 阿曼\tOM|旗\tflag: Oman\tOM|flag\t
    🇵🇦\t9\t0\t旗: 巴拿马\tPA|旗\tflag: Panama\tPA|flag\t
    🇵🇪\t9\t0\t旗: 秘鲁\tPE|旗\tflag: Peru\tPE|flag\t
    🇵🇫\t9\t0\t旗: 法属波利尼西亚\tPF|旗\tflag: French Polynesia\tPF|flag\t
    🇵🇬\t9\t0\t旗: 巴布亚新几内亚\tPG|旗\tflag: Papua New Guinea\tPG|flag\t
    🇵🇭\t9\t0\t旗: 菲律宾\tPH|旗\tflag: Philippines\tPH|flag\t
    🇵🇰\t9\t0\t旗: 巴基斯坦\tPK|旗\tflag: Pakistan\tPK|flag\t
    🇵🇱\t9\t0\t旗: 波兰\tPL|旗\tflag: Poland\tPL|flag\t
    🇵🇲\t9\t0\t旗: 圣皮埃尔和密克隆群岛\tPM|旗\tflag: St. Pierre & Miquelon\tPM|flag\t
    🇵🇳\t9\t0\t旗: 皮特凯恩群岛\tPN|旗\tflag: Pitcairn Islands\tPN|flag\t
    🇵🇷\t9\t0\t旗: 波多黎各\tPR|旗\tflag: Puerto Rico\tPR|flag\t
    🇵🇸\t9\t0\t旗: 巴勒斯坦领土\tPS|旗\tflag: Palestinian Territories\tPS|flag\t
    🇵🇹\t9\t0\t旗: 葡萄牙\tPT|旗\tflag: Portugal\tPT|flag\t
    🇵🇼\t9\t0\t旗: 帕劳\tPW|旗\tflag: Palau\tPW|flag\t
    🇵🇾\t9\t0\t旗: 巴拉圭\tPY|旗\tflag: Paraguay\tPY|flag\t
    🇶🇦\t9\t0\t旗: 卡塔尔\tQA|旗\tflag: Qatar\tQA|flag\t
    🇷🇪\t9\t0\t旗: 留尼汪\tRE|旗\tflag: Réunion\tRE|flag\t
    🇷🇴\t9\t0\t旗: 罗马尼亚\tRO|旗\tflag: Romania\tRO|flag\t
    🇷🇸\t9\t0\t旗: 塞尔维亚\tRS|旗\tflag: Serbia\tRS|flag\t
    🇷🇺\t9\t0\t旗: 俄罗斯\tRU|旗\tflag: Russia\tRU|flag\t
    🇷🇼\t9\t0\t旗: 卢旺达\tRW|旗\tflag: Rwanda\tRW|flag\t
    🇸🇦\t9\t0\t旗: 沙特阿拉伯\tSA|旗\tflag: Saudi Arabia\tSA|flag\t
    🇸🇧\t9\t0\t旗: 所罗门群岛\tSB|旗\tflag: Solomon Islands\tSB|flag\t
    🇸🇨\t9\t0\t旗: 塞舌尔\tSC|旗\tflag: Seychelles\tSC|flag\t
    🇸🇩\t9\t0\t旗: 苏丹\tSD|旗\tflag: Sudan\tSD|flag\t
    🇸🇪\t9\t0\t旗: 瑞典\tSE|旗\tflag: Sweden\tSE|flag\t
    🇸🇬\t9\t0\t旗: 新加坡\tSG|旗\tflag: Singapore\tSG|flag\t
    🇸🇭\t9\t0\t旗: 圣赫勒拿\tSH|旗\tflag: St. Helena\tSH|flag\t
    🇸🇮\t9\t0\t旗: 斯洛文尼亚\tSI|旗\tflag: Slovenia\tSI|flag\t
    🇸🇯\t9\t0\t旗: 斯瓦尔巴和扬马延\tSJ|旗\tflag: Svalbard & Jan Mayen\tSJ|flag\t
    🇸🇰\t9\t0\t旗: 斯洛伐克\tSK|旗\tflag: Slovakia\tSK|flag\t
    🇸🇱\t9\t0\t旗: 塞拉利昂\tSL|旗\tflag: Sierra Leone\tSL|flag\t
    🇸🇲\t9\t0\t旗: 圣马力诺\tSM|旗\tflag: San Marino\tSM|flag\t
    🇸🇳\t9\t0\t旗: 塞内加尔\tSN|旗\tflag: Senegal\tSN|flag\t
    🇸🇴\t9\t0\t旗: 索马里\tSO|旗\tflag: Somalia\tSO|flag\t
    🇸🇷\t9\t0\t旗: 苏里南\tSR|旗\tflag: Suriname\tSR|flag\t
    🇸🇸\t9\t0\t旗: 南苏丹\tSS|旗\tflag: South Sudan\tSS|flag\t
    🇸🇹\t9\t0\t旗: 圣多美和普林西比\tST|旗\tflag: São Tomé & Príncipe\tST|flag\t
    🇸🇻\t9\t0\t旗: 萨尔瓦多\tSV|旗\tflag: El Salvador\tSV|flag\t
    🇸🇽\t9\t0\t旗: 荷属圣马丁\tSX|旗\tflag: Sint Maarten\tSX|flag\t
    🇸🇾\t9\t0\t旗: 叙利亚\tSY|旗\tflag: Syria\tSY|flag\t
    🇸🇿\t9\t0\t旗: 斯威士兰\tSZ|旗\tflag: Eswatini\tSZ|flag\t
    🇹🇦\t9\t0\t旗: 特里斯坦-达库尼亚群岛\tTA|旗\tflag: Tristan da Cunha\tTA|flag\t
    🇹🇨\t9\t0\t旗: 特克斯和凯科斯群岛\tTC|旗\tflag: Turks & Caicos Islands\tTC|flag\t
    🇹🇩\t9\t0\t旗: 乍得\tTD|旗\tflag: Chad\tTD|flag\t
    🇹🇫\t9\t0\t旗: 法属南部领地\tTF|旗\tflag: French Southern Territories\tTF|flag\t
    🇹🇬\t9\t0\t旗: 多哥\tTG|旗\tflag: Togo\tTG|flag\t
    🇹🇭\t9\t0\t旗: 泰国\tTH|旗\tflag: Thailand\tTH|flag\t
    🇹🇯\t9\t0\t旗: 塔吉克斯坦\tTJ|旗\tflag: Tajikistan\tTJ|flag\t
    🇹🇰\t9\t0\t旗: 托克劳\tTK|旗\tflag: Tokelau\tTK|flag\t
    🇹🇱\t9\t0\t旗: 东帝汶\tTL|旗\tflag: Timor-Leste\tTL|flag\t
    🇹🇲\t9\t0\t旗: 土库曼斯坦\tTM|旗\tflag: Turkmenistan\tTM|flag\t
    🇹🇳\t9\t0\t旗: 突尼斯\tTN|旗\tflag: Tunisia\tTN|flag\t
    🇹🇴\t9\t0\t旗: 汤加\tTO|旗\tflag: Tonga\tTO|flag\t
    🇹🇷\t9\t0\t旗: 土耳其\tTR|旗\tflag: Türkiye\tTR|flag\t
    🇹🇹\t9\t0\t旗: 特立尼达和多巴哥\tTT|旗\tflag: Trinidad & Tobago\tTT|flag\t
    🇹🇻\t9\t0\t旗: 图瓦卢\tTV|旗\tflag: Tuvalu\tTV|flag\t
    🇹🇼\t9\t0\t旗: 台湾\tTW|旗\tflag: Taiwan\tTW|flag\t
    🇹🇿\t9\t0\t旗: 坦桑尼亚\tTZ|旗\tflag: Tanzania\tTZ|flag\t
    🇺🇦\t9\t0\t旗: 乌克兰\tUA|旗\tflag: Ukraine\tUA|flag\t
    🇺🇬\t9\t0\t旗: 乌干达\tUG|旗\tflag: Uganda\tUG|flag\t
    🇺🇲\t9\t0\t旗: 美国本土外小岛屿\tUM|旗\tflag: U.S. Outlying Islands\tUM|flag\t
    🇺🇳\t9\t0\t旗: 联合国\tUN|旗\tflag: United Nations\tUN|flag\t
    🇺🇸\t9\t0\t旗: 美国\tUS|旗\tflag: United States\tUS|flag\t
    🇺🇾\t9\t0\t旗: 乌拉圭\tUY|旗\tflag: Uruguay\tUY|flag\t
    🇺🇿\t9\t0\t旗: 乌兹别克斯坦\tUZ|旗\tflag: Uzbekistan\tUZ|flag\t
    🇻🇦\t9\t0\t旗: 梵蒂冈\tVA|旗\tflag: Vatican City\tVA|flag\t
    🇻🇨\t9\t0\t旗: 圣文森特和格林纳丁斯\tVC|旗\tflag: St. Vincent & Grenadines\tVC|flag\t
    🇻🇪\t9\t0\t旗: 委内瑞拉\tVE|旗\tflag: Venezuela\tVE|flag\t
    🇻🇬\t9\t0\t旗: 英属维尔京群岛\tVG|旗\tflag: British Virgin Islands\tVG|flag\t
    🇻🇮\t9\t0\t旗: 美属维尔京群岛\tVI|旗\tflag: U.S. Virgin Islands\tVI|flag\t
    🇻🇳\t9\t0\t旗: 越南\tVN|旗\tflag: Vietnam\tVN|flag\t
    🇻🇺\t9\t0\t旗: 瓦努阿图\tVU|旗\tflag: Vanuatu\tVU|flag\t
    🇼🇫\t9\t0\t旗: 瓦利斯和富图纳\tWF|旗\tflag: Wallis & Futuna\tWF|flag\t
    🇼🇸\t9\t0\t旗: 萨摩亚\tWS|旗\tflag: Samoa\tWS|flag\t
    🇽🇰\t9\t0\t旗: 科索沃\tXK|旗\tflag: Kosovo\tXK|flag\t
    🇾🇪\t9\t0\t旗: 也门\tYE|旗\tflag: Yemen\tYE|flag\t
    🇾🇹\t9\t0\t旗: 马约特\tYT|旗\tflag: Mayotte\tYT|flag\t
    🇿🇦\t9\t0\t旗: 南非\tZA|旗\tflag: South Africa\tZA|flag\t
    🇿🇲\t9\t0\t旗: 赞比亚\tZM|旗\tflag: Zambia\tZM|flag\t
    🇿🇼\t9\t0\t旗: 津巴布韦\tZW|旗\tflag: Zimbabwe\tZW|flag\t
    🏴󠁧󠁢󠁥󠁮󠁧󠁿\t9\t0\t旗: 英格兰\tgbeng|旗\tflag: England\tflag|gbeng\t
    🏴󠁧󠁢󠁳󠁣󠁴󠁿\t9\t0\t旗: 苏格兰\tgbsct|旗\tflag: Scotland\tflag|gbsct\t
    🏴󠁧󠁢󠁷󠁬󠁳󠁿\t9\t0\t旗: 威尔士\tgbwls|旗\tflag: Wales\tflag|gbwls\t
    """

    /// 一行一个符号：分类、符号、中文名（后面的别名只用来搜索，用「|」分开）、英文名（同上）
    static let symbols = """
    math\t+\t加号|加\tplus sign
    math\t−\t减号|减|负号\tminus sign
    math\t×\t乘号|乘|叉\tmultiplication sign|times
    math\t÷\t除号|除\tdivision sign
    math\t±\t正负号|加减\tplus-minus sign
    math\t∓\t负正号\tminus-plus sign
    math\t≠\t不等于|不等号\tnot equal to
    math\t≈\t约等于|大约\talmost equal to|approximately
    math\t≡\t恒等于|全等\tidentical to
    math\t≤\t小于等于\tless-than or equal to
    math\t≥\t大于等于\tgreater-than or equal to
    math\t≪\t远小于\tmuch less-than
    math\t≫\t远大于\tmuch greater-than
    math\t∝\t正比于\tproportional to
    math\t∞\t无穷大|无限\tinfinity
    math\t√\t根号|平方根\tsquare root
    math\t∛\t立方根\tcube root
    math\t∑\t求和|总和|西格玛\tsummation
    math\t∏\t求积|连乘\tproduct
    math\t∫\t积分\tintegral
    math\t∬\t二重积分\tdouble integral
    math\t∮\t曲线积分|环路积分\tcontour integral
    math\t∂\t偏导|偏微分\tpartial differential
    math\t∇\t梯度|那布拉\tnabla
    math\t∆\t增量|变化量\tincrement
    math\tπ\t圆周率|派\tpi
    math\t∠\t角\tangle
    math\t⊥\t垂直\tperpendicular
    math\t∥\t平行\tparallel to
    math\t⊙\t圆|圆心\tcircled dot
    math\t∵\t因为\tbecause
    math\t∴\t所以\ttherefore
    math\t∈\t属于\telement of
    math\t∉\t不属于\tnot an element of
    math\t⊂\t真包含于|子集\tsubset of
    math\t⊃\t真包含|超集\tsuperset of
    math\t⊆\t包含于\tsubset of or equal to
    math\t⊇\t包含\tsuperset of or equal to
    math\t∪\t并集|并\tunion
    math\t∩\t交集|交\tintersection
    math\t∅\t空集\tempty set
    math\t∀\t任意|所有\tfor all
    math\t∃\t存在\tthere exists
    math\t¬\t非|否定\tnot sign
    math\t∧\t且|合取\tlogical and
    math\t∨\t或|析取\tlogical or
    math\t⊕\t异或|直和\tcircled plus|xor
    math\t‰\t千分号|千分之\tper mille
    math\t‱\t万分号|万分之\tper ten thousand
    math\t°\t度|度数\tdegree sign
    math\t′\t角分|撇\tprime
    math\t″\t角秒|双撇\tdouble prime
    math\t½\t二分之一|一半\tone half
    math\t⅓\t三分之一\tone third
    math\t⅔\t三分之二\ttwo thirds
    math\t¼\t四分之一\tone quarter
    math\t¾\t四分之三\tthree quarters
    math\t⅕\t五分之一\tone fifth
    math\t⅛\t八分之一\tone eighth
    arrows\t←\t左箭头|向左\tleftwards arrow
    arrows\t→\t右箭头|向右\trightwards arrow
    arrows\t↑\t上箭头|向上\tupwards arrow
    arrows\t↓\t下箭头|向下\tdownwards arrow
    arrows\t↔\t左右箭头|双向\tleft right arrow
    arrows\t↕\t上下箭头\tup down arrow
    arrows\t↖\t左上箭头\tnorth west arrow
    arrows\t↗\t右上箭头\tnorth east arrow
    arrows\t↘\t右下箭头\tsouth east arrow
    arrows\t↙\t左下箭头\tsouth west arrow
    arrows\t⇐\t双线左箭头\tleftwards double arrow
    arrows\t⇒\t双线右箭头|推出|蕴含\trightwards double arrow|implies
    arrows\t⇔\t双线左右箭头|等价|当且仅当\tleft right double arrow|if and only if
    arrows\t⇑\t双线上箭头\tupwards double arrow
    arrows\t⇓\t双线下箭头\tdownwards double arrow
    arrows\t⟵\t长左箭头\tlong leftwards arrow
    arrows\t⟶\t长右箭头\tlong rightwards arrow
    arrows\t⟷\t长左右箭头\tlong left right arrow
    arrows\t➜\t粗右箭头\theavy round-tipped rightwards arrow
    arrows\t➤\t三角箭头\tarrowhead
    arrows\t↩\t返回箭头|回车\tleftwards arrow with hook
    arrows\t↪\t右弯箭头\trightwards arrow with hook
    arrows\t↻\t顺时针|刷新|重做\tclockwise open circle arrow|refresh
    arrows\t↺\t逆时针|撤销\tanticlockwise open circle arrow|undo
    arrows\t⇄\t左右互换|交换\trightwards arrow over leftwards arrow|swap
    arrows\t⇅\t上下互换|排序\tupwards arrow leftwards of downwards arrow|sort
    arrows\t▶\t右三角|播放\tblack right-pointing triangle|play
    arrows\t◀\t左三角\tblack left-pointing triangle
    arrows\t▸\t小右三角\tsmall right-pointing triangle
    arrows\t▾\t小下三角\tsmall down-pointing triangle
    numbers\t①\t带圈数字 1|圆圈 1\tcircled number 1
    numbers\t②\t带圈数字 2|圆圈 2\tcircled number 2
    numbers\t③\t带圈数字 3|圆圈 3\tcircled number 3
    numbers\t④\t带圈数字 4|圆圈 4\tcircled number 4
    numbers\t⑤\t带圈数字 5|圆圈 5\tcircled number 5
    numbers\t⑥\t带圈数字 6|圆圈 6\tcircled number 6
    numbers\t⑦\t带圈数字 7|圆圈 7\tcircled number 7
    numbers\t⑧\t带圈数字 8|圆圈 8\tcircled number 8
    numbers\t⑨\t带圈数字 9|圆圈 9\tcircled number 9
    numbers\t⑩\t带圈数字 10|圆圈 10\tcircled number 10
    numbers\t⑪\t带圈数字 11|圆圈 11\tcircled number 11
    numbers\t⑫\t带圈数字 12|圆圈 12\tcircled number 12
    numbers\t⑬\t带圈数字 13|圆圈 13\tcircled number 13
    numbers\t⑭\t带圈数字 14|圆圈 14\tcircled number 14
    numbers\t⑮\t带圈数字 15|圆圈 15\tcircled number 15
    numbers\t⑯\t带圈数字 16|圆圈 16\tcircled number 16
    numbers\t⑰\t带圈数字 17|圆圈 17\tcircled number 17
    numbers\t⑱\t带圈数字 18|圆圈 18\tcircled number 18
    numbers\t⑲\t带圈数字 19|圆圈 19\tcircled number 19
    numbers\t⑳\t带圈数字 20|圆圈 20\tcircled number 20
    numbers\t❶\t黑底圆圈数字 1\tnegative circled number 1
    numbers\t❷\t黑底圆圈数字 2\tnegative circled number 2
    numbers\t❸\t黑底圆圈数字 3\tnegative circled number 3
    numbers\t❹\t黑底圆圈数字 4\tnegative circled number 4
    numbers\t❺\t黑底圆圈数字 5\tnegative circled number 5
    numbers\t❻\t黑底圆圈数字 6\tnegative circled number 6
    numbers\t❼\t黑底圆圈数字 7\tnegative circled number 7
    numbers\t❽\t黑底圆圈数字 8\tnegative circled number 8
    numbers\t❾\t黑底圆圈数字 9\tnegative circled number 9
    numbers\t❿\t黑底圆圈数字 10\tnegative circled number 10
    numbers\t⑴\t带括号数字 1\tparenthesized number 1
    numbers\t⑵\t带括号数字 2\tparenthesized number 2
    numbers\t⑶\t带括号数字 3\tparenthesized number 3
    numbers\t⑷\t带括号数字 4\tparenthesized number 4
    numbers\t⑸\t带括号数字 5\tparenthesized number 5
    numbers\t⑹\t带括号数字 6\tparenthesized number 6
    numbers\t⑺\t带括号数字 7\tparenthesized number 7
    numbers\t⑻\t带括号数字 8\tparenthesized number 8
    numbers\t⑼\t带括号数字 9\tparenthesized number 9
    numbers\t⑽\t带括号数字 10\tparenthesized number 10
    numbers\t⒈\t带点数字 1\tnumber 1 full stop
    numbers\t⒉\t带点数字 2\tnumber 2 full stop
    numbers\t⒊\t带点数字 3\tnumber 3 full stop
    numbers\t⒋\t带点数字 4\tnumber 4 full stop
    numbers\t⒌\t带点数字 5\tnumber 5 full stop
    numbers\t⒍\t带点数字 6\tnumber 6 full stop
    numbers\t⒎\t带点数字 7\tnumber 7 full stop
    numbers\t⒏\t带点数字 8\tnumber 8 full stop
    numbers\t⒐\t带点数字 9\tnumber 9 full stop
    numbers\t⒑\t带点数字 10\tnumber 10 full stop
    numbers\tⅠ\t罗马数字 1\troman numeral 1
    numbers\tⅡ\t罗马数字 2\troman numeral 2
    numbers\tⅢ\t罗马数字 3\troman numeral 3
    numbers\tⅣ\t罗马数字 4\troman numeral 4
    numbers\tⅤ\t罗马数字 5\troman numeral 5
    numbers\tⅥ\t罗马数字 6\troman numeral 6
    numbers\tⅦ\t罗马数字 7\troman numeral 7
    numbers\tⅧ\t罗马数字 8\troman numeral 8
    numbers\tⅨ\t罗马数字 9\troman numeral 9
    numbers\tⅩ\t罗马数字 10\troman numeral 10
    numbers\tⅪ\t罗马数字 11\troman numeral 11
    numbers\tⅫ\t罗马数字 12\troman numeral 12
    numbers\tⅰ\t小写罗马数字 1\tsmall roman numeral 1
    numbers\tⅱ\t小写罗马数字 2\tsmall roman numeral 2
    numbers\tⅲ\t小写罗马数字 3\tsmall roman numeral 3
    numbers\tⅳ\t小写罗马数字 4\tsmall roman numeral 4
    numbers\tⅴ\t小写罗马数字 5\tsmall roman numeral 5
    numbers\tⅵ\t小写罗马数字 6\tsmall roman numeral 6
    numbers\tⅶ\t小写罗马数字 7\tsmall roman numeral 7
    numbers\tⅷ\t小写罗马数字 8\tsmall roman numeral 8
    numbers\tⅸ\t小写罗马数字 9\tsmall roman numeral 9
    numbers\tⅹ\t小写罗马数字 10\tsmall roman numeral 10
    numbers\tⅺ\t小写罗马数字 11\tsmall roman numeral 11
    numbers\tⅻ\t小写罗马数字 12\tsmall roman numeral 12
    numbers\t㈠\t带括号的一\tparenthesized ideograph 1
    numbers\t㈡\t带括号的二\tparenthesized ideograph 2
    numbers\t㈢\t带括号的三\tparenthesized ideograph 3
    numbers\t㈣\t带括号的四\tparenthesized ideograph 4
    numbers\t㈤\t带括号的五\tparenthesized ideograph 5
    numbers\t㈥\t带括号的六\tparenthesized ideograph 6
    numbers\t㈦\t带括号的七\tparenthesized ideograph 7
    numbers\t㈧\t带括号的八\tparenthesized ideograph 8
    numbers\t㈨\t带括号的九\tparenthesized ideograph 9
    numbers\t㈩\t带括号的十\tparenthesized ideograph 10
    numbers\t㊀\t带圈的一\tcircled ideograph 1
    numbers\t㊁\t带圈的二\tcircled ideograph 2
    numbers\t㊂\t带圈的三\tcircled ideograph 3
    numbers\t㊃\t带圈的四\tcircled ideograph 4
    numbers\t㊄\t带圈的五\tcircled ideograph 5
    numbers\t㊅\t带圈的六\tcircled ideograph 6
    numbers\t㊆\t带圈的七\tcircled ideograph 7
    numbers\t㊇\t带圈的八\tcircled ideograph 8
    numbers\t㊈\t带圈的九\tcircled ideograph 9
    numbers\t㊉\t带圈的十\tcircled ideograph 10
    punctuation\t「\t左直角引号|引号\tleft corner bracket
    punctuation\t」\t右直角引号|引号\tright corner bracket
    punctuation\t『\t左双直角引号|引号\tleft white corner bracket
    punctuation\t』\t右双直角引号|引号\tright white corner bracket
    punctuation\t【\t左方头括号|括号\tleft black lenticular bracket
    punctuation\t】\t右方头括号|括号\tright black lenticular bracket
    punctuation\t〔\t左六角括号|括号\tleft tortoise shell bracket
    punctuation\t〕\t右六角括号|括号\tright tortoise shell bracket
    punctuation\t《\t左书名号|书名号\tleft double angle bracket
    punctuation\t》\t右书名号|书名号\tright double angle bracket
    punctuation\t〈\t左单书名号|书名号\tleft angle bracket
    punctuation\t〉\t右单书名号|书名号\tright angle bracket
    punctuation\t“\t左双引号|引号\tleft double quotation mark
    punctuation\t”\t右双引号|引号\tright double quotation mark
    punctuation\t‘\t左单引号|引号\tleft single quotation mark
    punctuation\t’\t右单引号|撇号|引号\tright single quotation mark|apostrophe
    punctuation\t…\t省略号\thorizontal ellipsis
    punctuation\t—\t破折号|长横线\tem dash
    punctuation\t–\t连接号|短横线\ten dash
    punctuation\t·\t间隔号|中点\tmiddle dot
    punctuation\t•\t项目符号|圆点\tbullet
    punctuation\t※\t参考符号|注意\treference mark
    punctuation\t〃\t同上符号|同上\tditto mark
    punctuation\t々\t叠字符号\tideographic iteration mark
    punctuation\t〇\t零|圆圈\tideographic number zero
    punctuation\t§\t章节符号|节\tsection sign
    punctuation\t¶\t段落符号|段落\tpilcrow sign|paragraph
    punctuation\t†\t剑号|注释\tdagger
    punctuation\t‡\t双剑号\tdouble dagger
    punctuation\t¡\t倒感叹号\tinverted exclamation mark
    punctuation\t¿\t倒问号\tinverted question mark
    punctuation\t‽\t问叹号\tinterrobang
    punctuation\t¦\t断竖线\tbroken bar
    punctuation\t‖\t双竖线\tdouble vertical line
    punctuation\t⸺\t双字线|长破折号\ttwo-em dash
    punctuation\t〜\t波浪号\twave dash
    units\t℃\t摄氏度|温度\tdegree celsius
    units\t℉\t华氏度\tdegree fahrenheit
    units\t¥\t人民币|元|日元\tyen sign|yuan
    units\t€\t欧元\teuro sign
    units\t£\t英镑\tpound sign
    units\t₩\t韩元\twon sign
    units\t₽\t卢布\truble sign
    units\t₹\t卢比\tindian rupee sign
    units\t¢\t美分|分\tcent sign
    units\t₿\t比特币\tbitcoin sign
    units\t₫\t越南盾\tdong sign
    units\t฿\t泰铢\tbaht sign
    units\t™\t商标\ttrade mark sign
    units\t©\t版权\tcopyright sign
    units\t®\t注册商标\tregistered sign
    units\t℗\t录音版权\tsound recording copyright
    units\t№\t编号|号码\tnumero sign
    units\t℡\t电话\ttelephone sign
    units\t㎡\t平方米\tsquare metre
    units\t㎥\t立方米\tcubic metre
    units\t㎏\t千克|公斤\tkilogram
    units\t㎎\t毫克\tmilligram
    units\t㎝\t厘米\tcentimetre
    units\t㎜\t毫米\tmillimetre
    units\t㎞\t千米|公里\tkilometre
    units\t㏄\t立方厘米|毫升\tcubic centimetre
    units\t㎖\t毫升\tmillilitre
    units\tℓ\t升\tlitre
    units\tµ\t微\tmicro sign
    units\tΩ\t欧姆|电阻\tohm sign
    units\tÅ\t埃\tangstrom sign
    units\t㏒\t对数\tlog
    units\t㏑\t自然对数\tln
    shapes\t✓\t对勾|勾|正确\tcheck mark
    shapes\t✔\t粗对勾|勾\theavy check mark
    shapes\t✗\t叉|错误\tballot x
    shapes\t✘\t粗叉\theavy ballot x
    shapes\t☐\t方框|复选框\tballot box
    shapes\t☑\t打勾的方框|已选\tballot box with check
    shapes\t☒\t打叉的方框\tballot box with x
    shapes\t★\t实心五角星|星\tblack star
    shapes\t☆\t空心五角星|星\twhite star
    shapes\t●\t实心圆|圆点\tblack circle
    shapes\t○\t空心圆|圆圈\twhite circle
    shapes\t◎\t双圆|靶心\tbullseye
    shapes\t◆\t实心菱形|菱形\tblack diamond
    shapes\t◇\t空心菱形|菱形\twhite diamond
    shapes\t■\t实心方块|方块\tblack square
    shapes\t□\t空心方块|方框\twhite square
    shapes\t▲\t实心上三角|三角\tblack up-pointing triangle
    shapes\t△\t空心上三角|三角\twhite up-pointing triangle
    shapes\t▼\t实心下三角|三角\tblack down-pointing triangle
    shapes\t▽\t空心下三角|三角\twhite down-pointing triangle
    shapes\t♠\t黑桃|扑克\tspade suit
    shapes\t♥\t红心|扑克|爱心\theart suit
    shapes\t♣\t梅花|扑克\tclub suit
    shapes\t♦\t方片|扑克\tdiamond suit
    shapes\t♤\t空心黑桃\twhite spade suit
    shapes\t♡\t空心红心|爱心\twhite heart suit
    shapes\t♧\t空心梅花\twhite club suit
    shapes\t♢\t空心方片\twhite diamond suit
    shapes\t♪\t音符|音乐\teighth note
    shapes\t♫\t双音符|音乐\tbeamed eighth notes
    shapes\t♀\t女|女性\tfemale sign
    shapes\t♂\t男|男性\tmale sign
    shapes\t☀\t太阳|晴\tsun
    shapes\t☁\t云|阴\tcloud
    shapes\t☂\t伞|雨\tumbrella
    shapes\t☎\t电话\tblack telephone
    shapes\t✉\t信封|邮件\tenvelope
    shapes\t✂\t剪刀\tscissors
    shapes\t✎\t铅笔|编辑\tlower right pencil
    shapes\t⚠\t警告|注意\twarning sign
    shapes\t☯\t太极|阴阳\tyin yang
    shapes\t✿\t花\tblack florette
    shapes\t❀\t花\twhite florette
    shapes\t❤\t心|爱心\theavy black heart
    greek\tα\t阿尔法|希腊字母\talpha
    greek\tβ\t贝塔|希腊字母\tbeta
    greek\tγ\t伽马|希腊字母\tgamma
    greek\tδ\t德尔塔|希腊字母\tdelta
    greek\tε\t艾普西隆|希腊字母\tepsilon
    greek\tζ\t泽塔|希腊字母\tzeta
    greek\tη\t伊塔|希腊字母\teta
    greek\tθ\t西塔|希腊字母\ttheta
    greek\tι\t约塔|希腊字母\tiota
    greek\tκ\t卡帕|希腊字母\tkappa
    greek\tλ\t兰姆达|希腊字母\tlambda
    greek\tμ\t缪|希腊字母\tmu
    greek\tν\t纽|希腊字母\tnu
    greek\tξ\t克西|希腊字母\txi
    greek\tο\t欧米克隆|希腊字母\tomicron
    greek\tπ\t派|希腊字母\tpi
    greek\tρ\t柔|希腊字母\trho
    greek\tσ\t西格玛|希腊字母\tsigma
    greek\tτ\t陶|希腊字母\ttau
    greek\tυ\t宇普西隆|希腊字母\tupsilon
    greek\tφ\t斐|希腊字母\tphi
    greek\tχ\t希|希腊字母\tchi
    greek\tψ\t普西|希腊字母\tpsi
    greek\tω\t欧米伽|希腊字母\tomega
    greek\tΑ\t大写阿尔法|希腊字母\tcapital alpha
    greek\tΒ\t大写贝塔|希腊字母\tcapital beta
    greek\tΓ\t大写伽马|希腊字母\tcapital gamma
    greek\tΔ\t大写德尔塔|希腊字母\tcapital delta
    greek\tΕ\t大写艾普西隆|希腊字母\tcapital epsilon
    greek\tΖ\t大写泽塔|希腊字母\tcapital zeta
    greek\tΗ\t大写伊塔|希腊字母\tcapital eta
    greek\tΘ\t大写西塔|希腊字母\tcapital theta
    greek\tΙ\t大写约塔|希腊字母\tcapital iota
    greek\tΚ\t大写卡帕|希腊字母\tcapital kappa
    greek\tΛ\t大写兰姆达|希腊字母\tcapital lambda
    greek\tΜ\t大写缪|希腊字母\tcapital mu
    greek\tΝ\t大写纽|希腊字母\tcapital nu
    greek\tΞ\t大写克西|希腊字母\tcapital xi
    greek\tΟ\t大写欧米克隆|希腊字母\tcapital omicron
    greek\tΠ\t大写派|希腊字母\tcapital pi
    greek\tΡ\t大写柔|希腊字母\tcapital rho
    greek\tΣ\t大写西格玛|希腊字母\tcapital sigma
    greek\tΤ\t大写陶|希腊字母\tcapital tau
    greek\tΥ\t大写宇普西隆|希腊字母\tcapital upsilon
    greek\tΦ\t大写斐|希腊字母\tcapital phi
    greek\tΧ\t大写希|希腊字母\tcapital chi
    greek\tΨ\t大写普西|希腊字母\tcapital psi
    greek\tΩ\t大写欧米伽|希腊字母\tcapital omega
    scripts\t⁰\t上标 0|次方\tsuperscript 0
    scripts\t¹\t上标 1|次方\tsuperscript 1
    scripts\t²\t上标 2|平方\tsuperscript 2
    scripts\t³\t上标 3|立方\tsuperscript 3
    scripts\t⁴\t上标 4|次方\tsuperscript 4
    scripts\t⁵\t上标 5|次方\tsuperscript 5
    scripts\t⁶\t上标 6|次方\tsuperscript 6
    scripts\t⁷\t上标 7|次方\tsuperscript 7
    scripts\t⁸\t上标 8|次方\tsuperscript 8
    scripts\t⁹\t上标 9|次方\tsuperscript 9
    scripts\t⁺\t上标加号\tsuperscript plus
    scripts\t⁻\t上标减号\tsuperscript minus
    scripts\t⁼\t上标等号\tsuperscript equals
    scripts\t⁽\t上标左括号\tsuperscript left parenthesis
    scripts\t⁾\t上标右括号\tsuperscript right parenthesis
    scripts\tⁿ\t上标 n|n 次方\tsuperscript n
    scripts\tⁱ\t上标 i\tsuperscript i
    scripts\t₀\t下标 0\tsubscript 0
    scripts\t₁\t下标 1\tsubscript 1
    scripts\t₂\t下标 2\tsubscript 2
    scripts\t₃\t下标 3\tsubscript 3
    scripts\t₄\t下标 4\tsubscript 4
    scripts\t₅\t下标 5\tsubscript 5
    scripts\t₆\t下标 6\tsubscript 6
    scripts\t₇\t下标 7\tsubscript 7
    scripts\t₈\t下标 8\tsubscript 8
    scripts\t₉\t下标 9\tsubscript 9
    scripts\t₊\t下标加号\tsubscript plus
    scripts\t₋\t下标减号\tsubscript minus
    scripts\t₌\t下标等号\tsubscript equals
    scripts\t₍\t下标左括号\tsubscript left parenthesis
    scripts\t₎\t下标右括号\tsubscript right parenthesis
    scripts\tₐ\t下标 a\tsubscript a
    scripts\tₑ\t下标 e\tsubscript e
    scripts\tₒ\t下标 o\tsubscript o
    scripts\tₓ\t下标 x\tsubscript x
    keyboard\t⌘\tCommand 键|命令键|cmd\tcommand key
    keyboard\t⌥\tOption 键|选项键|alt\toption key
    keyboard\t⇧\tShift 键|上档键\tshift key
    keyboard\t⌃\tControl 键|控制键|ctrl\tcontrol key
    keyboard\t⎋\tEsc 键|退出键\tescape key
    keyboard\t⏎\tReturn 键|回车键|换行\treturn key
    keyboard\t⌫\tDelete 键|删除键|退格\tdelete key|backspace
    keyboard\t⌦\t向前删除键\tforward delete key
    keyboard\t⇥\tTab 键|制表键\ttab key
    keyboard\t⇤\t反向 Tab\tback tab
    keyboard\t⇪\tCaps Lock 键|大写锁定\tcaps lock key
    keyboard\t⏏\t推出键\teject key
    keyboard\t⌽\t电源键\tpower key
    keyboard\t⇞\tPage Up 键|上翻页\tpage up key
    keyboard\t⇟\tPage Down 键|下翻页\tpage down key
    keyboard\t↖\tHome 键\thome key
    keyboard\t↘\tEnd 键\tend key
    keyboard\t␣\t空格键\tspace key
    """
}
