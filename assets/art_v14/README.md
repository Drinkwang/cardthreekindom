# 四格营地与女将美术

2026-10-17，使用内置 `image_gen.imagegen` 生成并接入当前工程。旧资源保留。

| 文件 | 用途 | 实际尺寸 | 排列 |
| --- | --- | --- | --- |
| [camp_atlas.png](camp_atlas.png) | 休息页商店、构筑、技能、基建四格及商店插画 | 1254×1254 | 2列2行，每格627×627 |
| [female_heroes.png](female_heroes.png) | 8位女将主卡、构筑头像与收藏 | 1774×887 | 4列2行，每格443.5×443.5 |

女将顺序：G57黄月英、G58貂蝉、G59孙尚香、G60大乔、G61小乔、G62甄宓、G63蔡文姬、G64祝融。

生成器返回的原生尺寸与提示词建议尺寸不同，保留原图；运行裁切读取真实图像尺寸，不假设整数格宽。

完整实际提示词与尺寸记录：[四格场景](camp_generation.json)、[女将肖像](female_generation.json)。角色映射见[female_heroes_catalog.json](female_heroes_catalog.json)。
