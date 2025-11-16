# __init__.py
#
# This file turns the "monsters" folder into a Python package
# AND automatically loads every monster file so all monsters
# register themselves inside MONSTER_DATABASE.

from .monster import Monster, register_monster, get_monster, MONSTER_DATABASE

# Import every monster family (this runs their register_monster calls)
from .goblins import *
from .bandits import *
from .bats import *
from .cultists import *
from .golem import *
from .harpy import *
from .kobold import *
from .orc import *
from .skeletons import *
from .wolfs import *
from .slimes import *
from .spider import *
from .troll import *
from .wraith import *
