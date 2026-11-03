-- Which routes have the highest average arrival delay, excluding cancelled trips?”;
select route_id,route_name,round(avg(dl),2) as avg from (select tr.route_id,r.route_name,timestampdiff(minute,tr.scheduled_arrival,t.actual_arrival) as dl
from actual_trips t join trip_schedules tr on tr.schedule_id=t.schedule_id 
join routes r on r.route_id=tr.route_id where t.trip_status='COMPLETED') as m group by route_id,route_name order by avg desc limit 1;


-- Calculate the average departure delay and average arrival delay for every route. Also classify each 
-- route as Reliable, Moderate Delay, or High Delay based on its average arrival delay.
select tr.route_id,r.route_name,round(avg(timestampdiff(minute,tr.scheduled_departure,t.actual_departure)),2) as depdl
,round(avg(timestampdiff(minute,tr.scheduled_arrival,t.actual_arrival)),2) as arrdel,case when round(avg(timestampdiff(minute,tr.scheduled_arrival,t.actual_arrival)),2) >15 then 'High delay'
when round(avg(timestampdiff(minute,tr.scheduled_arrival,t.actual_arrival)),2) >10 then 'modelate_delay' else 'reliable' end as label from trip_schedules tr join actual_trips t
 on t.schedule_id=tr.schedule_id join routes r on r.route_id=tr.route_id where t.trip_status='COMPLETED' group by tr.route_id,r.route_name;



-- Find the top 3 routes with the highest average arrival delay and display their route names,
-- average delays, and ranks.
select distinct * from (select tr.route_id,rn.route_name,avg(timestampdiff(minute,tr.scheduled_arrival,r.actual_arrival)) as avg_delay,
dense_rank()over(order by avg(timestampdiff(minute,tr.scheduled_arrival,r.actual_arrival))desc) as rnk
 from actual_trips r join trip_schedules tr on r.schedule_id=tr.schedule_id join routes rn on rn.route_id=tr.route_id where r.trip_status=
 'COMPLETED'group by tr.route_id) as m where rnk <=3;


-- Find each route's average arrival delay and compare it with the previous-ranked route's average 
-- delay.  Calculate the difference in minutes.
select * from(select r.*,lag(avg_delay) over(order by avg_delay desc)-avg_delay as diff from(select tr.route_id,r.route_name,avg(timestampdiff(minute,tr.scheduled_arrival,t.actual_arrival)) as avg_delay
, rank() over(order by avg(timestampdiff(minute,tr.scheduled_arrival,t.actual_arrival)) desc) as rnk from routes r join trip_schedules tr on tr.route_id=r.route_id join actual_trips t on t.schedule_id=tr.schedule_id
where t.trip_status='COMPLETED' group by tr.route_id,r.route_name) as r)  as m;


-- Identify routes whose average arrival delay is higher than the overall average arrival
--  delay across all completed trips.
select tr.route_id,r.route_name,round(avg(timestampdiff(minute,tr.scheduled_arrival,t.actual_arrival)),2) as avg_arrival
from routes r join trip_schedules tr on tr.route_id=r.route_id join actual_trips t on t.schedule_id=tr.schedule_id
where t.trip_status='COMPLETED' group by tr.route_id,r.route_name having avg_arrival>
(select round(avg(timestampdiff(minute,tr.scheduled_arrival,t.actual_arrival)),2) as a
from routes r join trip_schedules tr on tr.route_id=r.route_id join actual_trips t on t.schedule_id=tr.schedule_id
where t.trip_status='COMPLETED');

-- Calculate the on-time performance percentage for each route. Consider a completed trip on time 
-- if its actual arrival is no more than 5 minutes later than its scheduled arrival. 
-- Rank the routes from highest to lowest on-time performance.
select route_id,label,round((label/c)*100,2) as ontime_percentage,rank()over(order by round((label/c)*100,2)desc) as rnk from(select tr.route_id,count(*)as c,sum(case when timestampdiff(minute,tr.scheduled_arrival,t.actual_arrival) <=5 then 1 else 0 end) as label
 from actual_trips t join trip_schedules tr on tr.schedule_id=t.schedule_id where t.trip_status='COMPLETED'
group by tr.route_id) as m;


-- Identify the top 3 busiest stops based on the total number of passengers boarding at each stop
-- . Display the stop name, total boardings, and rank.
select * from(select s.stop_id,s.stop_name,sum(p.boardings) as tot,rank()over(order by sum(p.boardings) desc) as rnk  from stops s join passenger_counts p on p.stop_id=s.stop_id
group by s.stop_id) as m where rnk<=3 ;


-- Identify the routes where passenger demand exceeds 50% of the assigned vehicle capacity. 
-- Calculate the passenger demand and capacity utilization percentage for each route, 
-- then rank the routes from highest to lowest utilization.
select route_id,route_name,sum(max_onboard) as passenger_demand, round((sum(max_onboard)/sum(capacity))*100,2) as capacity_utilization, rank() over(order by (sum(max_onboard)/sum(capacity))*100 desc) as rnk
from (select r.route_id,r.route_name,t.actual_trip_id,max(p.onboard_count) as max_onboard, vr.capacity as capacity
from routes r join trip_schedules tr on tr.route_id=r.route_id join actual_trips t on t.schedule_id=tr.schedule_id
join passenger_counts p on p.actual_trip_id=t.actual_trip_id join vehicles vr on vr.vehicle_id=tr.vehicle_id where t.trip_status='COMPLETED'
group by r.route_id,r.route_name,t.actual_trip_id,vr.capacity) as m group by route_id,route_name having (sum(max_onboard)/sum(capacity))*100 > 50;

-- Identify routes with the highest trip cancellation rate. Calculate the cancellation percentage
--  for each route and rank them from highest to lowest.
select route_id,route_name,round((can/tot)*100,2) as can_rate,rank()over(order by round((can/tot)*100,2) desc) as rnk from (select r.route_id,r.route_name,sum(case when t.trip_status='CANCELLED' then 1 else 0 end )as can,count(*) as tot from routes r join trip_schedules tr on tr.route_id=r.route_id
join actual_trips t on t.schedule_id=tr.schedule_id group by r.route_id,r.route_name) as m order by can_rate desc;
select * from passenger_counts;


-- Identify the busiest hours of the day based on total passenger boardings. 
-- Rank the hours from highest to lowest passenger demand.
select * from(select date(recorded_at) as date,hour(recorded_at) as hour,sum(boardings) as tot ,rank() over(order by sum(boardings) desc) as rnk from passenger_counts
group by date,hour) as m order by tot desc;


-- Compare Passenger Demand Between Consecutive Hours
select *, total_boardings - previous_hour_boardings as demand_change from (select *, lag(total_boardings) over
 (partition by recorded_date order by recorded_hour) as previous_hour_boardings from (select date(recorded_at) 
 as recorded_date, hour(recorded_at) as recorded_hour, sum(boardings) as total_boardings from passenger_counts 
 group by date(recorded_at), hour(recorded_at)) as hourly_demand) as hourly_comparison where previous_hour_boardings is not null;
 
--  Identify the hours where passenger boardings increased compared to the previous hour.
--  Calculate the change in passenger demand and rank the hours by the increase.
select d.*,tot-la as diff,rank() over(order by tot-la desc) as rnk from(select date(t.recorded_at) as date,hour(t.recorded_at) as hour,sum(t.boardings) as tot,lag(sum(t.boardings) ) 
over(partition by date(t.recorded_at) order by hour(t.recorded_at) ) as la from passenger_counts t group by date,hour) as d where la is not null and tot>la;


-- Identify routes where arrival delays are increasing over successive trips. Calculate the delay difference 
-- between consecutive trips and rank routes by their largest delay increase.
select route_id, max(delay - previous_delay) as maximum_delay_increase, dense_rank() over
 (order by max(delay - previous_delay) desc) as rnk from (select *, lag(delay) over (partition by
 route_id, trip_date order by actual_trip_id) as previous_delay from (select tr.route_id, tr.trip_date, 
 t.actual_trip_id, timestampdiff(minute, tr.scheduled_arrival, t.actual_arrival) as delay from trip_schedules tr join actual_trips t on t.schedule_id = tr.schedule_id where t.trip_status = 'completed') as trip_delays) as delay_comparison where previous_delay is not null and delay > previous_delay group by route_id;

-- Identify routes where arrival delays are consistently increasing across consecutive trips. 
-- Find routes that have at least 2 consecutive delay increases.
select * from (select *, lag(delay, 1) over (partition by route_id, trip_date order by actual_trip_id) as prev_delay, lag(delay, 2) over (partition by route_id, trip_date order by actual_trip_id)
 as prev_prev_delay from (select tr.route_id, tr.trip_date, t.actual_trip_id, timestampdiff(minute, 
 tr.scheduled_arrival, t.actual_arrival) as delay from trip_schedules tr join actual_trips t on t.schedule_id = tr.schedule_id where t.trip_status = 'completed') as trip_delays) as delay_sequence where prev_delay is not null and prev_prev_delay is not null and delay > prev_delay and prev_delay > prev_prev_delay;

-- Identify routes where arrival delays fluctuate significantly between consecutive trips. Calculate the absolute difference 
-- in delay between consecutive trips and rank routes by their average delay fluctuation.
select k.route_id,round(avg(abs),2),dense_rank() over(order by avg(abs)desc) as rnk from(select d.*,abs(del-pre) as abs
 from(select tr.route_id,t.actual_trip_id,date(tr.scheduled_arrival) as sd,date(t.actual_arrival) as ad,
 time(tr.scheduled_arrival) as st,time(t.actual_arrival) as at,timestampdiff(minute, tr.scheduled_arrival
 ,t.actual_arrival) as del ,LAG(TIMESTAMPDIFF(MINUTE,tr.scheduled_arrival,t.actual_arrival)) OVER (PARTITION BY tr.route_id, tr.trip_date ORDER BY tr.scheduled_departure) AS pre from trip_schedules tr join actual_trips t on 
t.schedule_id=tr.schedule_id where t.trip_status='COMPLETED') as d where pre is not null) as k group by route_id;



-- Identify routes where at least 80% of completed trips arrive on time.
--  Rank these routes by their on-time performance percentage, from highest to lowest.
select tr.route_id,round((sum(case when timestampdiff(minute,tr.scheduled_arrival,t.actual_arrival)<=5 then 1 else 0 end )/count(*))*100.0,2)as label
,dense_rank() over(order by (sum(case when timestampdiff(minute,tr.scheduled_arrival,t.actual_arrival)<=5 then 1 else 0 end )/count(*))*100 desc) as rnk from trip_schedules tr join actual_trips t on t.schedule_id=tr.schedule_id where t.trip_status='COMPLETED' group by 
 tr.route_id having label>=80;


-- Identify routes where trip cancellations are associated with poor on-time performance. For each route, calculate:
-- Total scheduled trips.
-- Number of cancelled trips.
-- Cancellation percentage.
-- On-time performance percentage among completed trips.
-- Return only routes with a cancellation rate greater than 10%. Rank them by cancellation percentage from highest to lowest.
select route_id, count(*) as scheduled_trips, sum(case when t.trip_status='cancelled' then 1 else 0 end) as can_trips,
 round(sum(case when t.trip_status='cancelled' then 1 else 0 end)/count(*)*100,2) as can_perc, 
 round(sum(case when t.trip_status='completed' and timestampdiff(minute,tr.scheduled_arrival,t.actual_arrival)<=5
 then 1 else 0 end)/sum(case when t.trip_status='completed' then 1 else 0 end)*100,2) as ontime_perc, rank()
 over(order by sum(case when t.trip_status='cancelled' then 1 else 0 end)/count(*)*100 desc) as rnk from trip_schedules tr
 join actual_trips t on t.schedule_id=tr.schedule_id group by route_id having can_perc>10;
 

--  route-wise passenger demand vs capacity
-- For each route, calculate:
-- total passenger boardings
-- maximum onboard passengers recorded
-- vehicle capacity
-- capacity utilization percentage
-- rank routes by capacity utilization in descending order
select route_id,sum(pb) as total_boardings,max(mo) as max_onboard_passengers,round(avg(capacity),2) 
as avg_vehicle_capacity,round((sum(mo)/sum(capacity))*100,2) as capacity_utilization,rank() over(order by (sum(mo)/sum(capacity))*100 desc) as rnk from (select tr.route_id,t.actual_trip_id,sum(p.boardings) as pb,max(p.onboard_count) as mo,v.capacity from actual_trips t join trip_schedules tr on tr.schedule_id=t.schedule_id join vehicles v on v.vehicle_id=tr.vehicle_id join passenger_counts p on p.actual_trip_id=t.actual_trip_id 
where t.trip_status='completed' group by tr.route_id,t.actual_trip_id,v.capacity) as l group by route_id; 


-- For each route, identify routes where passenger demand frequently exceeds vehicle capacity.
-- Calculate:
-- Total trips
-- Number of overcrowded trips
-- Overcrowding percentage
-- Average maximum onboard passengers
-- Rank routes by overcrowding percentage in descending order
-- Condition: A trip is overcrowded when its maximum recorded onboard passengers exceed the assigned vehicle's capacity
select route_id,count(*) as total_trips,sum(case when onb>capacity then 1 else 0 end) as overcro,round((sum(case when onb>capacity then 1 else 0 end)/count(*))*100,2) as crowd_perc
,round(avg(onb),2) as avg_on,rank()over(order by round((sum(case when onb>capacity then 1 else 0 end)/count(*))*100,2) desc) as rnk from(select tr.route_id,t.actual_trip_id,max(p.onboard_count) as onb,v.capacity from 
actual_trips t join trip_schedules tr on tr.schedule_id=t.schedule_id join passenger_counts p
 on p.actual_trip_id=t.actual_trip_id join vehicles v on v.vehicle_id=tr.vehicle_id
group by tr.route_id,t.actual_trip_id,v.capacity) as p group by route_id;


-- Identify routes where passenger demand is increasing over time.
-- For each route:
-- Calculate daily total passenger boardings.
-- Compare each day's boardings with the previous day's boardings.
-- Calculate the percentage growth in passenger demand.
-- Rank routes based on their average daily demand growth percentage.
select route_id,round(avg(growth_perc),2) as avg_growth,rank() over(order by round(avg(growth_perc),2) desc) as rnk from(select tr.route_id,date(p.recorded_at) as date,sum(p.boardings) as boardings,lag(sum(p.boardings) )over
(partition by tr.route_id order by date(p.recorded_at) asc) as prev,((sum(p.boardings)-lag(sum(p.boardings) )over
(partition by tr.route_id order by date(p.recorded_at) asc))/nullif(lag(sum(p.boardings) )over
(partition by tr.route_id order by date(p.recorded_at) asc),0))*100 as growth_perc from actual_trips t
join trip_schedules tr on tr.schedule_id=t.schedule_id join passenger_counts p on p.actual_trip_id=t.actual_trip_id
group by tr.route_id,date) as d where prev is not null group by route_id;
 
 
--  Identify routes where passenger demand has decreased for two consecutive recor)ded days. Display the route ID, date, 
--  current day's total boardings, previous day's total boardings, and percentage decrease.
select f.*,((boardings-aft)/nullif(boardings,0))*100 as descc from(select tr.route_id,date(p.recorded_at) as date,sum(boardings) as boardings,
lead(sum(boardings))over(partition by tr.route_id order by date(p.recorded_at) asc) as aft,
lead(sum(boardings),2)over(partition by tr.route_id order by date(p.recorded_at) asc) as aft1 from  
passenger_counts p join actual_trips t on t.actual_trip_id=p.actual_trip_id join 
trip_schedules tr on tr.schedule_id=t.schedule_id group by tr.route_id,date) as f where boardings>aft and aft>aft1 and aft is not null and aft1 is not null;


-- Identify trips where passenger occupancy exceeds 80% of the vehicle's total capacity. Display the route ID, actual trip ID, 
-- vehicle ID, maximum onboard passenger count, vehicle capacity and capacity utilization percentage. 
-- Rank the trips from highest to lowest capacity utilization.
select tr.route_id,t.actual_trip_id,v.vehicle_id,max(p.onboard_count) as mxon,v.capacity,(max(p.onboard_count)/v.capacity)*100 as uti ,rank() over(order by (max(p.onboard_count)/v.capacity)*100 desc) as rnk from actual_trips t join trip_schedules tr on tr.schedule_id=t.schedule_id 
join vehicles v on v.vehicle_id=tr.vehicle_id join passenger_counts p on p.actual_trip_id=t.actual_trip_id group by tr.route_id,t.actual_trip_id,v.vehicle_id having uti>80;


-- Identify the busiest recorded time for each route based on the total number of passengers onboard.
--  Display the route ID, recorded date, recorded hour, total passenger count
-- , and rank the hours within each route from highest to lowest passenger demand.
select * from(select tr.route_id,date(p.recorded_at) as date,hour(p.recorded_at) as hour,sum(p.onboard_count) as tot ,rank()over(partition by tr.route_id order by sum(p.onboard_count)  desc) as rnk from actual_trips t join trip_schedules tr on tr.schedule_id=t.schedule_id join passenger_counts p 
on p.actual_trip_id=t.actual_trip_id group by route_id,date,hour) as f where rnk=1;


-- Identify routes where passenger demand during peak hours is higher than during non-peak hours. Display the route ID,
--  peak-hour passenger demand, non-peak-hour passenger demand, and the percentage difference between them.
select route_id,max(case when label='peak' then tot end ) as peak,max(case when label='non peak' then tot end )as non_peak ,
((max(case when label='peak' then tot end )-max(case when label='non peak' then tot end ))/nullif((max(case when label='non peak' 
then tot end )),0)*100) as per
 from(select tr.route_id,case when hour(p.recorded_at) between 7 and 9 or hour(recorded_at)
 between 17 and 19 then 'peak' else 'non peak' end as label,sum(boardings) as tot
  from passenger_counts p join actual_trips t on t.actual_trip_id=p.actual_trip_id join trip_schedules tr on
  tr.schedule_id=t.schedule_id group by route_id,label) as o group by route_id having peak>non_peak;
  
  
--   Identify routes where passenger boarding demand increased for three consecutive recorded dates. Display the route
--   ID, the boarding demand for each of the three dates, and the overall percentage growth from the first date to the third date.
select *,round(((aft1-tot)/tot)*100,2)as gr from(select tr.route_id,date(p.recorded_at) as date,sum(p.boardings) as tot,
lead(sum(p.boardings))over(partition by tr.route_id order by date(p.recorded_at)
 asc) as aft,lead(sum(p.boardings),2)over(partition by tr.route_id order by date(p.recorded_at)
 asc) as aft1 from actual_trips t join trip_schedules tr on 
tr.schedule_id=t.schedule_id join passenger_counts p on p.actual_trip_id=t.actual_trip_id group by tr.route_id,date)as
 t where aft1 is not null and aft is not null and  tot<aft and aft<aft1;
 
 
--  Identify routes with the highest percentage of delayed trips. Display the route ID, total completed trips,
--  delayed trips, and delay percentage. Rank routes from highest to lowest delay percentage.
select *,round(((delayed_trips/completed_trips)*100),2)as delayed_percentage ,rank() over(order by round(((
delayed_trips/completed_trips)*100),2) desc) as rnk from(select tr.route_id,sum(case when  t.trip_status='COMPLETED' then 1 else 0 end) as completed_trips,sum(case when t.trip_status='COMPLETED' and timestampdiff(minute,tr.scheduled_arrival,
t.actual_arrival)>=5 then 1 else 0 end) as delayed_trips from actual_trips t   join trip_schedules tr on 
tr.schedule_id=t.schedule_id group by tr.route_id) as f ;


-- Identify routes where on-time performance improved compared with the previous recorded date. Display the route ID,
--  current day's on-time percentage, previous recorded day's on-time percentage, and the percentage-point improvement.
select *, ontime_perc-prev as improvement from (select *, lag(ontime_perc) over(partition by route_id order by trip_date)
 as prev from (select tr.route_id,tr.trip_date,count(*) as completed_trips,sum(case when timestampdiff(minute,tr.scheduled
 _arrival,t.actual_arrival)<=5 then 1 else 0 end) as ontime,round(sum(case when timestampdiff(minute,tr.scheduled_arrival,
 t.actual_arrival)<=5 then 1 else 0 end)/count(*)*100,2) as ontime_perc from trip_schedules tr join actual_trips t on
 t.schedule_id=tr.schedule_id where t.trip_status='COMPLETED' group by tr.route_id,tr.trip_date) as m) as n where prev is not 
 null and ontime_perc>prev;
 

--  Identify routes where avg trip delays are consistently increasing across three consecutive recorded service dates.
select * from(select route_id,date,round(avg(delay),2) as avg_delay,lag(round(avg(delay),2))over(partition by route_id order by date) as prev,lag(round(avg(delay),2),2)over(partition by route_id order by date) as prev1 from(select tr.route_id,t.actual_trip_id,date(tr.trip_date) as date ,greatest(0,timestampdiff(minute,tr.scheduled_arrival,
t.actual_arrival)) as delay from actual_trips t join trip_schedules tr on tr.schedule_id=t.schedule_id  where t.trip_status='COMPLETED'
group by tr.route_id,t.actual_trip_id,date) as z group by route_id,date) as f where prev is not null and prev1 is not null and avg_delay>prev and prev>prev1;


-- Classify routes based on the severity of their average trip delays.
-- Calculate the average delay in minutes for each route using completed trips, 
-- then classify each route into these categories:
select tr.route_id,count(*) as total_trips,round(avg(greatest(0,timestampdiff(minute,tr.scheduled_arrival,t.actual_arrival)))
,2) as avg_delay,case when avg(greatest(0,timestampdiff(minute,tr.scheduled_arrival,t.actual_arrival)))<=5 then 'On Time' 
when avg(greatest(0,timestampdiff(minute,tr.scheduled_arrival,t.actual_arrival)))<=15 then 'Moderate Delay' else 'Severe Delay
' end as delay_category from trip_schedules tr join actual_trips t on t.schedule_id=tr.schedule_id where 
t.trip_status='COMPLETED' group by tr.route_id;


-- Identify routes where higher passenger demand is associated with higher average trip delays.
select route_id,tot,delay,'high demand-high delay' as label from (select *,avg(tot) 
over() as at,avg(delay) over() as ad from (select tr.route_id,sum(p.boardings) as tot,round(avg(timestampdiff(minute,tr.scheduled_arrival,t.actual_arrival)),2) as delay from trip_schedules tr join actual_trips t on t.schedule_id=tr.schedule_id join passenger_counts p on p.actual_trip_id=t.actual_trip_id
 where t.trip_status='completed' group by tr.route_id) as z) as l where tot>at and delay>ad;

--  Passenger Demand vs. Vehicle Capacity and Trip Delays**
-- Identify routes with high passenger demand, high vehicle capacity utilization, and high average trip delays.
-- Display the `route_id`, `total_boardings`, `capacity_utilization (%)`, and `avg_delay`.
-- Classify routes based on the overall average demand, capacity utilization, and delay. Identify routes that may require additional vehicle capacity.
select route_id,tot as total_boardings,avg_cap as capacity_utilization,avg_delay,
case when tot>oat and avg_cap>oac and avg_delay>oad then 'high demand-high utilization-high delay' else 'does not meet all three conditions' end as classification,
case when tot>oat and avg_cap>oac then 'additional capacity may be required' else 'no immediate capacity requirement' end as capacity_recommendation
from (select *,avg(tot) over() as oat,avg(avg_cap) over() as oac,avg(avg_delay) over() as oad from (select route_id,sum(tot) as tot,round(avg(delay),2) as avg_delay,round(avg(uti),2) as avg_cap from (select tr.route_id,t.actual_trip_id,sum(p.boardings) as tot,greatest(0,timestampdiff(minute,tr.scheduled_arrival,t.actual_arrival)) as delay,round((max(p.onboard_count)/v.capacity)*100,2) as uti from actual_trips t join trip_schedules tr on tr.schedule_id=t.schedule_id join passenger_counts p on p.actual_trip_id=t.actual_trip_id join vehicles v on v.vehicle_id=tr.vehicle_id where t.trip_status='completed' and date(p.recorded_at)=tr.trip_date group by tr.route_id,
t.actual_trip_id,tr.scheduled_arrival,t.actual_arrival,v.capacity) as f group by route_id) as m) as g;

-- Route Performance Ranking
-- Rank all routes based on their overall performance using average trip delay and passenger demand.
-- Display route_id, total_boardings, avg_delay, and performance_rank.
-- Goal: Identify the routes with the best and worst overall performance.
select route_id,total_boardings,avg_delay,rank() over(order by demand_rank+delay_rank) as
 performance_rank from (select *,rank() over(order by total_boardings desc) as demand_rank,rank() over(order by avg_delay asc) as delay_rank from (select tr.route_id,sum(p.boardings) as total_boardings,round(avg(greatest(0,timestampdiff(minute,tr.scheduled_arrival,t.actual_arrival))),2) as avg_delay from trip_schedules tr join actual_trips t on t.schedule_id=tr.schedule_id join passenger_counts p on p.actual_trip_id=t.actual_trip_id
 where t.trip_status='completed' and date(p.recorded_at)=tr.trip_date group by tr.route_id) as a) as b;
 
 
-- Chennai transport management team wants to identify whether buses are maintaining their scheduled departure 
-- intervals.Sometimes two buses scheduled 20 minutes apart may actually depart only 5 minutes apart.
--  This creates vehicle bunching. Sometimes the gap becomes too large, creating service gaps for passengers.
with a as (select tr.route_id,tr.trip_date,t.actual_trip_id,lead(t.actual_trip_id) over(partition by tr.route_id,tr.trip_date order by 
tr.scheduled_departure) as next_trip_id,tr.scheduled_departure as s_current,lead(tr.scheduled_departure) 
over(partition by tr.route_id,tr.trip_date order by tr.scheduled_departure) as s_next,t.actual_departure as 
a_current,lead(t.actual_departure) over(partition by tr.route_id,tr.trip_date order by tr.scheduled_departure)
 as a_next from trip_schedules tr join actual_trips t on t.schedule_id=tr.schedule_id where t.trip_status='completed' and t.actual_departure is not null),gap as (select *,timestampdiff(minute,s_current,s_next) as scheduled_gap,timestampdiff(minute,a_current,a_next) as actual_gap from a where s_next is not null and s_current is not null and a_current is not null and a_next is not null) select route_id,trip_date,actual_trip_id,next_trip_id,scheduled_gap,actual_gap,case when scheduled_gap<=0 then 'invalid schedule gap' when actual_gap<0.5*scheduled_gap then 'bus bunching' when actual_gap>1.5*scheduled_gap then 'service gap' else 'normal' end as label from gap;


-- Build the Complete Route Path:
-- For every route, generate its complete stop sequence using a Recursive CTE.
with recursive a as(
select rs.route_id,rs.stop_id,rs.stop_sequence,s.stop_name,cast(s.stop_name as char(1000)) as cha from stops s join route_stops rs on s.stop_id=rs.stop_id
where rs.stop_sequence=1
union all
select rs.route_id,rs.stop_id,rs.stop_sequence,s.stop_name,concat(r.cha,'->',s.stop_name) as ch
from a r join route_stops rs on rs.route_id=r.route_id and rs.stop_sequence=r.stop_sequence+1 join stops s on s.stop_id=rs.stop_id
)
select *from a order by route_id,stop_sequence;


-- Identify routes that share common stops.
select a.route_id,b.route_id,s.stop_name,count(*)over(partition by a.route_id,b.route_id) as count from route_stops a join route_stops b on a.stop_id=b.stop_id
 and a.route_id<b.route_id join stops s on s.stop_id=a.stop_id order by a.route_id,b.route_id,s.stop_name;
 
--  Identify all stops from the stops table that have never appeared in the passenger_counts table.
select s.stop_id,s.stop_name,s.stop_type,s.area from stops s where not exists(select 1 from passenger_counts r where r.stop_id=s.stop_id);



-- Identify which routes experience overcrowding during peak hours compared with non-peak hours.
with trip_capacity as (select tr.route_id,t.actual_trip_id,max(p.onboard_count) as 
max_passengers,v.capacity,case when hour(p.recorded_at) between 7 and 9 or hour(p.recorded_at) between 17 and 19 then 'peak' else 'non peak' end as period from actual_trips t join trip_schedules tr on tr.schedule_id=t.schedule_id join vehicles v on v.vehicle_id=tr.vehicle_id join passenger_counts p on p.actual_trip_id=t.actual_trip_id where t.trip_status='completed' group by tr.route_id,t.actual_trip_id,v.capacity,period) select route_id,count(case when period='peak' and max_passengers>capacity then 1 end) as peak_overcrowded_trips,count(case when period='non peak' and max_passengers>capacity then 1 end) as non_peak_overcrowded_trips,count(case when period='peak' then 1 end) as total_peak_trips,count(case when period='non peak' then 1 end) as total_non_peak_trips,round(count(case when period='peak' and max_passengers>capacity then 1 end)/nullif(count(case when period='peak' then 1 end),0)*100,2) as peak_overcrowding_percentage,round(count(case when period='non peak' and max_passengers>capacity then 1 end)/nullif(count(case when period='non peak' then 1 end),0)*100,2) as non_peak_overcrowding_percentage
 from trip_capacity group by route_id order by peak_overcrowding_percentage desc;

