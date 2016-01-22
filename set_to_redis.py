#!/usr/bin/python
#coding:utf-8
import redis
r = redis.StrictRedis(host='10.0.3.61', port=6379, db=0)
data = '''{"group2":[{"ip":"10.0.4.146","current_weight":10,"weight":10},{"ip":"10.0.4.147","current_weight":10,"weight":10}],"group1":[{"ip":"10.0.4.175","current_weight":"10","weight":"10"},{"ip":"10.0.4.176","current_weight":"10","weight":"10"}],"deploy":0,"weight":{"group2":"10","group":"10"},"testiplist":["10.0.0.111","127.0.0.1"]}'''
r.set("my_object",data)
