import random
from collections import deque

class Task:
    def __init__(self, tid, execution_time, multiplier, arrival_time):
        self.tid = tid
        self.total_execution_time = execution_time  
        self.remaining_time = execution_time
        self.multiplier = multiplier  
        self.arrival_time = arrival_time  
        self.priority = None  
        self.current_queue = None
        self.state = "READY"

        self.wait_time = 0
        self.turnaround_time = 0
        self.response_time = None
        self.start_time = None
        self.end_time = None
        self.cpu_slices = 0
        self.queue_transitions = 0

    def __repr__(self):
        return (f"Task{self.tid}(rem:{self.remaining_time}, pri:{self.priority}, arr:{self.arrival_time})")

def gen_tasks(seed=69):
    random.seed(seed)
    small_range = (10, 100)
    medium_range = (120, 500)
    large_range = (600, 1200)
    very_large_range = (3000, 10000)

    counts = {"small":20, "medium":20, "large":20, "very_large":20}
    exec_times = []
    for _ in range(counts["small"]):
        exec_times.append(random.randint(*small_range))
    for _ in range(counts["medium"]):
        exec_times.append(random.randint(*medium_range))
    for _ in range(counts["large"]):
        exec_times.append(random.randint(*large_range))
    for _ in range(counts["very_large"]):
        exec_times.append(random.randint(*very_large_range))

    min_et = min(exec_times)
    max_et = max(exec_times)

    def compute_mp(et):
        base = 0.01
        scale = 0.98
        mp = base + scale * ((et - min_et) / (max_et - min_et))
        return min(max(mp, 0.01), 0.99)

    arrival_times = [random.uniform(0, 20000) for _ in range(len(exec_times))]

    tasks = []
    tid = 1
    for et, at in zip(exec_times, arrival_times):
        mp = compute_mp(et)
        task = Task(tid, et, mp, arrival_time=at)
        
        if mp < 0.33:
            task.priority = 3
        elif mp < 0.66:
            task.priority = 2
        else:
            task.priority = 1
        task.current_queue = task.priority
        tasks.append(task)
        tid += 1
    return tasks


class RRPlusPriorityScheduler:
    def __init__(self, tasks, time_slices):
        self.tasks = tasks
        self.queues = {3: deque(), 2: deque(), 1: deque()}
        self.time_slices = time_slices
        self.clock = 0.0  
        self.finished_tasks = []
        self.context_switches = 0
        
        self.enqueued_tasks = set()

    def all_finished(self):
        return all(task.state == "FINISHED" for task in self.tasks)

    def enqueue_arrived_tasks(self):
        for task in self.tasks:
            if (task.arrival_time <= self.clock and 
                task.state != "FINISHED" and 
                task.tid not in self.enqueued_tasks):
                self.queues[task.priority].append(task)
                self.enqueued_tasks.add(task.tid)

    def run(self):
        while not self.all_finished():
            self.enqueue_arrived_tasks()
            
            ran_task = False
            for prio in [3,2,1]:
                queue = self.queues[prio]
                ready_queue = deque([t for t in queue if t.state != "FINISHED" and t.arrival_time <= self.clock])
                if not ready_queue:
                    continue
                
                task = ready_queue.popleft()
                self.queues[prio] = deque([t for t in queue if t != task])
                
                if task.start_time is None:
                    task.start_time = self.clock
                    task.response_time = self.clock - task.arrival_time
                task.state = "RUNNING"
                
                time_run = min(self.time_slices[prio], task.remaining_time)
                
                self.clock += time_run
                
                for p in [3,2,1]:
                    for other in self.queues[p]:
                        if (other.tid != task.tid and other.arrival_time <= self.clock and other.state != "FINISHED"):
                            other.wait_time += time_run
                
                task.remaining_time -= time_run
                task.cpu_slices += 1
                
                self.context_switches += 1
                
                if task.remaining_time <= 0:
                    task.state = "FINISHED"
                    task.end_time = self.clock
                    task.turnaround_time = task.end_time - task.arrival_time
                    self.finished_tasks.append(task)
                    if task.tid in self.enqueued_tasks:
                        self.enqueued_tasks.discard(task.tid)
                else:
                    task.state = "READY"
                    self.queues[prio].append(task)
                
                ran_task = True
                break
            
            if not ran_task:
                future_arrivals = [t.arrival_time for t in self.tasks if t.state != "FINISHED" and t.arrival_time > self.clock]
                if not future_arrivals:
                    break
                self.clock = min(future_arrivals)

def main():
    tasks = gen_tasks(seed=69)
    print("Generated Tasks:")
    print("ID | Execution Time (ms) | Multiplier | Arrival Time (ms) | Priority")
    print("---|---------------------|------------|-------------------|---------")
    for t in sorted(tasks, key=lambda x: x.tid):
        print(f"{t.tid:>2} | {t.total_execution_time:>19} | {t.multiplier:>10.2f} | {t.arrival_time:>17.2f} | {t.priority:>7}")
    
    time_slices = {3: 100, 2: 120, 1: 140}
    print("\nTime Slices (ms):", time_slices, "\n")
    
    scheduler = RRPlusPriorityScheduler(tasks, time_slices)
    scheduler.run()
    
    finished = sorted(scheduler.finished_tasks, key=lambda t: t.tid)
    n = len(finished)
    avg_turn = sum(t.turnaround_time for t in finished) / n
    avg_wait = sum(t.wait_time for t in finished) / n
    avg_resp = sum(t.response_time for t in finished) / n
    total_slices = sum(t.cpu_slices for t in finished)
    throughput = n / (scheduler.clock / 1000) if scheduler.clock > 0 else float('inf')
    
    print("\nTask Metrics")
    print("ID | Total Exec(ms) | Multiplier | Arrival (ms) | Priority | Turnaround (ms) | Waiting (ms) | Response (ms) | CPU Slices")
    for t in finished:
        print(f"{t.tid:>2} | {t.total_execution_time:>14} | {t.multiplier:>10.2f} | {t.arrival_time:>12.2f} | {t.priority:>7} | "
              f"{t.turnaround_time:>15.2f} | {t.wait_time:>11.2f} | {t.response_time:>13.2f} | {t.cpu_slices:>10}")
    
    print("\nAggregate Metrics")
    print(f"Total simulated CPU time: {scheduler.clock:.2f} ms")
    print(f"Average Turnaround Time : {avg_turn:.2f} ms")
    print(f"Average Waiting Time    : {avg_wait:.2f} ms")
    print(f"Average Response Time   : {avg_resp:.2f} ms")
    print(f"Total CPU slices used   : {total_slices}")
    print(f"Context switches         : {scheduler.context_switches}")
    print(f"Throughput              : {throughput:.2f} tasks/sec")

if __name__ == "__main__":
    main()
