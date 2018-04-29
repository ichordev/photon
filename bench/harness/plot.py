#!/usr/bin/env python
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np
from datetime import datetime
import sys
from tqdm import tqdm

RSS = 'RSS(MB)'
READ = 'read(MB)'
WRITE = 'written(MB)'
USER = 'user cpu time(sec)'
KERNEL = 'kernel cpu time(sec)'
NAMES = [RSS, READ, WRITE, USER, KERNEL]

httpArg = sys.argv[1]
resArg = sys.argv[2]
destArg = sys.argv[3]

http = pd.read_csv(httpArg)
res = pd.read_csv(resArg)

http['time'] = pd.to_datetime(http['time'])
res['time'] = pd.to_datetime(res['time'])

results = http.copy()
for n in NAMES:
    results[n] = pd.Series(0,index=np.arange(len(http)), dtype=np.float64)

for i in tqdm(range(len(http))):
    start = http['time'][i]
    if i != len(http) - 1:
        end = http['time'][i+1]
        slice = res[(res['time'] > start) & (res['time'] < end)]
    else:
        slice = res[(res['time'] > start)]
    results[RSS][i] = slice[RSS].agg('max')
    results[USER][i] = slice[USER].agg('sum')
    results[KERNEL][i] = slice[KERNEL].agg('sum')
    results[READ][i] = slice[READ].agg('sum')
    results[WRITE][i] = slice[WRITE].agg('sum')

results.to_csv(destArg)
