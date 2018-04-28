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

http = list(http_stats)
res = list(resources)

print(http[0])
print(res[0])

res_slices = []
for i in range(len(http)):
	slice = []
	for j in range(len(resources)):
		start = res[0]['time'] if i > 0 else http[i - 1]['time']
		if res[j] > start and res[j] < http[i]['time']:
			slice.append(res[j])
	res_slices.append(slice)

for i in range(len(http)):
	print(http[i], len(res_slices))
