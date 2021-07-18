select train_num, time_prib,
TIME_FORMAT(time_otpr, '%H:%i') as time_otpr, date_go,
 station as station, plat, path,
if(time_delay='00:00:00','',TIME_FORMAT(time_delay, '%i')) as time_delay,ostanovki,
krome, stay_on_tab
 from actual_train where (in_or_out <>"œ–»¡.")and(train_num<>'')and(station<>'ÃŒ— ¬¿ ﬂ–') ORDER BY sorting, date_go, glob_time limit 20;