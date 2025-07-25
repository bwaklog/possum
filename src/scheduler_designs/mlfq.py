import time
import random
from collections import defaultdict, deque

#There seem to be 10k ways of implementing this, here's the one I'm trying rn
#3 levels of priority [0,2]
#Round robin in each, FIFO in the last one
#Pre-emption if a higher priority thread arrives
#Unlike before, arrival time is also randomized now
#Every n seconds, all threads get promoted to the highest priroity queue
#Time quantums 0-3 = [150, 170, 200, unlimited]
#We also need to simulate tasks that yield control so it moves to an upper priority
#Doing randomized promotion of 30% tasks every 7 seconds to simulate that



class Thread:
    def __init__(self, thread_id, priority, burst_time, arrival_time):
        self.thread_id = thread_id
        self.priority = priority 
        self.burst_time = burst_time
        self.remaining_time = burst_time
        self.state = "READY"
        self.arrival_time = arrival_time
        self.start_time = None
        self.end_time = None
        self.waiting_time = 0
        self.response_time = None
        self.last_run_time = None  

    def __repr__(self):
        return f"Thread(id={self.thread_id}, pri={self.priority}, rem={self.remaining_time:.2f}, state={self.state})"


class Scheduler:
    def __init__(self):
        
        self.priority_queues = {2: deque(), 1: deque(), 0: deque()}
        self.threads = []
        self.time_quantums = {2: 150, 1: 170, 0: None}  # None means FCFS, no preemption via quantum
        self.current_time = time.time()*1000
        self.context_switches = 0
        self.last_promotion_time = self.current_time
        self.last_random_promotion_time = self.current_time
        self.random_promotion_interval = 7000
        self.global_promotion_interval = 7000
        self.random_promotion_fraction = 0.3

    def add_thread(self, thread):
        self.threads.append(thread)

    def enqueue_thread(self, thread):
        queue = self.priority_queues[thread.priority]
        queue.append(thread)

    def sort_queues_by_arrival(self):
        
        q0 = self.priority_queues[0]
        self.priority_queues[0] = deque(sorted(q0, key=lambda t: t.arrival_time))

    def all_threads_finished(self):
        return all(t.state == "FINISHED" for t in self.threads)

    def get_ready_threads(self):
        return [t for t in self.threads if t.arrival_time <= self.current_time and t.state != "FINISHED"]

    def promote_all(self):
        print(f"\n--- Global promotion of all threads to priority 2 ---")
        for p in [0,1]:
            queue = self.priority_queues[p]
            while queue:
                t = queue.popleft()
                if t.state != "FINISHED" and t.arrival_time <= self.current_time:
                    t.priority = 2
                    self.priority_queues[2].append(t)
        for t in self.get_ready_threads():
            if t.priority != 2 and t.state != "FINISHED":
                old_queue = self.priority_queues[t.priority]
                if t in old_queue:
                    old_queue.remove(t)
                t.priority = 2
                self.priority_queues[2].append(t)

    def randomized_promotion(self):
        promotable = []
        for p in [0,1]:
            promotable.extend([t for t in self.priority_queues[p] if t.state != "FINISHED" and t.arrival_time <= self.current_time])
        if not promotable:
            return
        num_to_promote = max(1, int(len(promotable) * self.random_promotion_fraction))
        promote_list = random.sample(promotable, k=num_to_promote)
        print(f"\n--- Random promotion of {num_to_promote} threads ---")
        for t in promote_list:
            old_p = t.priority
            new_p = old_p + 1
            if new_p > 2:
                new_p = 2
            if new_p == old_p:
                continue
            print(f"Promoting Thread {t.thread_id} from {old_p} -> {new_p}")
            if t in self.priority_queues[old_p]:
                self.priority_queues[old_p].remove(t)
            t.priority = new_p
            self.priority_queues[new_p].append(t)

    def schedule(self):
        
        self.current_time = time.time()*1000

        for t in self.get_ready_threads():
            found_in_queue = False
            for q in self.priority_queues.values():
                if t in q:
                    found_in_queue = True
                    break
            if not found_in_queue and t.state != "FINISHED" and t.state != "RUNNING":
                self.priority_queues[t.priority].append(t)

        self.sort_queues_by_arrival()

        for p in [2,1,0]:
            queue = self.priority_queues[p]
            q_len = len(queue)
            if q_len == 0:
                continue

            if p == 0:
                t = queue[0]
                if t.arrival_time > self.current_time or t.state == "FINISHED":
                    continue
                return t
            else:
                for _ in range(q_len):
                    t = queue.popleft()
                    if t.state == "FINISHED" or t.arrival_time > self.current_time:
                        queue.append(t)
                        continue
                    queue.append(t)  
                    return t
        return None

    def run(self):
        print("\n--- Starting MLFQ Scheduling Simulation ---")
        start_sim_time = time.time()*1000

        current_thread = None
        quantum_used = 0
        previous_time = self.current_time

        while not self.all_threads_finished():
            now = time.time()*1000
            elapsed = now-previous_time
            previous_time=now
            self.current_time = now

            for t in self.threads:
                if t.state == "READY" and t.arrival_time <= self.current_time:
                    t.waiting_time += elapsed

            if now - self.last_promotion_time >= self.global_promotion_interval:
                self.promote_all()
                self.last_promotion_time = now

            if now - self.last_random_promotion_time >= self.random_promotion_interval:
                self.randomized_promotion()
                self.last_random_promotion_time = now

            next_thread = self.schedule()

            if next_thread is None:
                time.sleep(0.01)
                current_thread = None
                quantum_used = 0
                continue

            if current_thread and current_thread.state == "RUNNING":
                if next_thread.priority > current_thread.priority:
                    print(f"Preempting Thread {current_thread.thread_id} due to higher priority Thread {next_thread.thread_id}")
                    current_thread.state = "READY"
                    if current_thread not in self.priority_queues[current_thread.priority]:
                        self.priority_queues[current_thread.priority].append(current_thread)
                    current_thread = next_thread
                    quantum_used = 0
                else:
                    if quantum_used >= self.time_quantums.get(current_thread.priority, None) and current_thread.priority != 0:
                        old_p = current_thread.priority
                        if old_p > 0:
                            new_p = old_p -1
                        else:
                            new_p = old_p

                        print(f"Demoting Thread {current_thread.thread_id} from priority {old_p} to {new_p} after quantum expiration")
                        current_thread.priority = new_p
                        current_thread.state = "READY"
                        if current_thread not in self.priority_queues[new_p]:
                            self.priority_queues[new_p].append(current_thread)
                        current_thread = next_thread
                        quantum_used = 0

                    else:
                        pass
            else:
                current_thread = next_thread
                quantum_used = 0

            tq = self.time_quantums[current_thread.priority]
            if tq is None:
                execution_time = current_thread.remaining_time
            else:
                execution_time = tq - quantum_used
                if execution_time > current_thread.remaining_time:
                    execution_time = current_thread.remaining_time

            print(f"\nExecuting Thread {current_thread.thread_id} , Priority={current_thread.priority} , Remaining={current_thread.remaining_time:.2f}s , Quantum slice: {execution_time:.2f}s")
            time.sleep(execution_time/1000)
            self.current_time += execution_time

            current_thread.remaining_time -= execution_time
            quantum_used += execution_time

            if current_thread.start_time is None:
                current_thread.start_time = self.current_time - execution_time
            if current_thread.response_time is None:
                current_thread.response_time = current_thread.start_time - current_thread.arrival_time

            if current_thread.remaining_time <= 0:
                current_thread.state = "FINISHED"
                current_thread.end_time = self.current_time
                print(f"Thread {current_thread.thread_id} finished execution")
                current_thread = None
                quantum_used = 0
                self.context_switches += 1
            else:
                if tq is not None and quantum_used >= tq:
                    old_p = current_thread.priority
                    if old_p > 0:
                        new_p = old_p -1
                    else:
                        new_p = old_p
                    if new_p != old_p:
                        print(f"Demoting Thread {current_thread.thread_id} from priority {old_p} to {new_p} after quantum expiration")
                    current_thread.priority = new_p
                    current_thread.state = "READY"

                    
                    if current_thread not in self.priority_queues[new_p]:
                        self.priority_queues[new_p].append(current_thread)

                    current_thread = None
                    quantum_used = 0
                    self.context_switches += 1
                else:
                    
                    if current_thread.state == "RUNNING" or current_thread.state == "READY":
                        
                        if current_thread.priority != 0:
                            q = self.priority_queues[current_thread.priority]
                            if current_thread in q:
                                q.remove(current_thread)
                            q.append(current_thread)
                        else:
                            
                            pass

        
        end_sim_time = time.time()*1000
        total_time = end_sim_time - start_sim_time

        total_turnaround = sum(t.end_time - t.arrival_time for t in self.threads)
        total_waiting = sum(t.waiting_time for t in self.threads)
        total_response = sum(t.response_time for t in self.threads if t.response_time is not None)
        n = len(self.threads)

        print("\nSummary for mlfq-")
        print(f"Total time elapsed: {total_time:.2f} seconds")
        print(f"Total context switches: {self.context_switches}")
        print(f"!!! Average turnaround time: {total_turnaround/n:.2f} ms")
        print(f"!!! Average waiting time: {total_waiting/n:.2f} ms")
        print(f"!!! Average response time: {total_response/n:.2f} ms")
        print(f"!!! Throughput: {n/(total_time/1000):.2f} threads/sec")
        cpu_burst_sum = sum(t.burst_time for t in self.threads)
        print(f"CPU Utilization: {(cpu_burst_sum/total_time)*100:.2f}%")

        print("\nThreads final states:")
        for t in self.threads:
            print(f"Thread {t.thread_id}: Priority={t.priority}, Finished={t.state=='FINISHED'}")

def main():
    
    random.seed(69)

    num_threads = 80
    priorities = [random.randint(0,2) for _ in range(num_threads)]
    #burst_times = [random.uniform(1,10) for _ in range(num_threads)]
    burst_times = (
        [random.uniform(10, 100) for _ in range(1,21)] +
        [random.uniform(120, 500) for _ in range(21, 41)] +
        [random.uniform(600, 1200) for _ in range(41, 61)]+
        [random.uniform(3000, 10000) for _ in range(61, 81)]
    )
    start_arrival_time = time.time()*1000
    arrival_times = [start_arrival_time + random.uniform(0,2000) for _ in range(num_threads)]

    scheduler = Scheduler()

    for i in range(num_threads):
        t = Thread(thread_id=i,
                   priority=priorities[i],
                   burst_time=burst_times[i],
                   arrival_time=arrival_times[i])
        print(f"Created Thread {i} , Priority={priorities[i]}, Burst={burst_times[i]:.2f}s, Arrival={arrival_times[i]-start_arrival_time:.2f}s after start")
        scheduler.add_thread(t)

    scheduler.run()


if __name__ == "__main__":
    main()
