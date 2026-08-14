# frozen_string_literal: true

# The Köppen-Geiger climate zone list (D-017).
#
# 45 rows in three self-parented levels. The names are ECHOcommunity's, because
# they are what the GMCC selector shows today and continuity matters more than
# matching a paper's wording - `D` is "Continental" here and "Cold" in Beck,
# both in common use. Three genuine errors in those names are corrected on the
# way in: "Climante", "Clomate", and a double space in the Dsa name.
#
# `authoritative` means "appears in Beck et al. 2018", the machine-readable map
# legend: the 5 groups and the 30 classes, but not the 8 subgroups, which are
# ECHO's own intermediate level, nor BSn/BWn. The `n` third letter (frequent
# fog - Lima, Walvis Bay) is recognised in the classical scheme; it is absent
# from Beck only because map rasters do not resolve fog. So `authoritative` is a
# statement about the map product, not about legitimacy.
#
# Kept apart from KoppenZoneSeeder so the table can be read, reviewed and
# diffed as data, without the seeding logic wrapped around it.
module KoppenZoneData
  SOURCE = 'Köppen–Geiger classical scheme'
  VERSION = 'Beck et al. 2018, Scientific Data 5:180214'
  SNAPSHOT = Date.new(2018, 10, 30)

  # code, parent, in Beck 2018?, name
  GROUPS = [
    ['A', nil, true, 'Tropical Climate'],
    ['B', nil, true, 'Arid Climate'],
    ['C', nil, true, 'Temperate Climate'],
    ['D', nil, true, 'Continental Climate'],
    ['E', nil, true, 'Polar Climate']
  ].freeze

  SUBGROUPS = [
    ['BS', 'B', false, 'Arid Steppe Climate'],
    ['BW', 'B', false, 'Arid Desert Climate'],
    ['Cf', 'C', false, 'Temperate Climate without Dry Season'],
    ['Cs', 'C', false, 'Temperate Climate with Dry Summer'],
    ['Cw', 'C', false, 'Temperate Climate with Dry Winter'],
    ['Df', 'D', false, 'Continental Climate without Dry Season'],
    ['Ds', 'D', false, 'Continental Climate with Dry Summer'],
    ['Dw', 'D', false, 'Continental Climate with Dry Winter']
  ].freeze

  CLASSES = [
    ['Af',  'A',  true,  'Tropical Rainforest Climate'],
    ['Am',  'A',  true,  'Tropical Monsoon Climate'],
    ['Aw',  'A',  true,  'Tropical Savanna Climate'],
    ['BSh', 'BS', true,  'Hot Arid Steppe Climate'],
    ['BSk', 'BS', true,  'Cold Arid Steppe Climate'],
    ['BSn', 'BS', false, 'Mild Arid Steppe Climate'],       # was "Climante"
    ['BWh', 'BW', true,  'Hot Arid Desert Climate'],
    ['BWk', 'BW', true,  'Cold Arid Desert Climate'],
    ['BWn', 'BW', false, 'Mild Arid Desert Climate'],       # was "Clomate"
    ['Cfa', 'Cf', true,  'Temperate Climate without Dry Season with Hot Summer'],
    ['Cfb', 'Cf', true,  'Temperate Climate without Dry Season with Warm Summer'],
    ['Cfc', 'Cf', true,  'Temperate Climate without Dry Season with Cold Summer'],
    ['Csa', 'Cs', true,  'Temperate Climate with Hot Dry Summer'],
    ['Csb', 'Cs', true,  'Temperate Climate with Warm Dry Summer'],
    ['Csc', 'Cs', true,  'Temperate Climate with Cold Dry Summer'],
    ['Cwa', 'Cw', true,  'Temperate Climate with Dry Winter and Hot Summer'],
    ['Cwb', 'Cw', true,  'Temperate Climate with Dry Winter and Warm Summer'],
    ['Cwc', 'Cw', true,  'Temperate Climate with Dry Winter and Cold Summer'],
    ['Dfa', 'Df', true,  'Continental Climate without Dry Season with Hot Summer'],
    ['Dfb', 'Df', true,  'Continental Climate without Dry Season with Warm Summer'],
    ['Dfc', 'Df', true,  'Continental Climate without Dry Season with Cold Summer'],
    ['Dfd', 'Df', true,  'Continental Climate without Dry Season with Very Cold Winter'],
    ['Dsa', 'Ds', true,  'Continental Climate with Hot Dry Summer'], # had a double space
    ['Dsb', 'Ds', true,  'Continental Climate with Warm Dry Summer'],
    ['Dsc', 'Ds', true,  'Continental Climate with Cold Dry Summer'],
    ['Dsd', 'Ds', true,  'Continental Climate with Dry Summer and Very Cold Winter'],
    ['Dwa', 'Dw', true,  'Continental Climate with Dry Winter and Hot Summer'],
    ['Dwb', 'Dw', true,  'Continental Climate with Dry Winter and Warm Summer'],
    ['Dwc', 'Dw', true,  'Continental Climate with Dry Winter and Cold Summer'],
    ['Dwd', 'Dw', true,  'Continental Climate with Very Cold Dry Winter'],
    ['EF',  'E',  true,  'Eternal Winter'],
    ['ET',  'E',  true,  'Tundra']
  ].freeze

  ALL = (GROUPS.map { |r| r + ['group'] } +
         SUBGROUPS.map { |r| r + ['subgroup'] } +
         CLASSES.map { |r| r + ['class'] }).freeze
end
