#!/usr/bin/env python
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np
import sys

http = sys.argv[1]
res = sys.argv[2]

http_stats = pd.read_csv(http)
resources = pd.read_csv(res)

http_stats['time'] = pd.to_datetime(http_stats['time'])
resources['time'] = pd.to_datetime(resources['time'])
