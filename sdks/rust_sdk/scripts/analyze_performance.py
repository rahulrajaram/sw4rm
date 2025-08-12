#!/usr/bin/env python3
"""
Performance Analysis Script for SW4RM Rust SDK

This script analyzes benchmark results and provides performance insights.
It can parse criterion output and generate reports with recommendations.

Usage:
    python scripts/analyze_performance.py [benchmark_results_dir]
"""

import json
import sys
import os
from pathlib import Path
from typing import Dict, List, Any
import matplotlib.pyplot as plt
import numpy as np

class PerformanceAnalyzer:
    def __init__(self, results_dir: str = "target/criterion"):
        self.results_dir = Path(results_dir)
        self.benchmarks = {}
        
    def load_benchmark_results(self) -> Dict[str, Any]:
        """Load all benchmark results from the criterion directory"""
        if not self.results_dir.exists():
            print(f"❌ Benchmark results directory not found: {self.results_dir}")
            print("Run: cargo bench --bench performance_benchmarks")
            return {}
            
        results = {}
        
        # Find all benchmark.json files
        for bench_dir in self.results_dir.iterdir():
            if bench_dir.is_dir():
                json_file = bench_dir / "base" / "estimates.json"
                if json_file.exists():
                    try:
                        with open(json_file, 'r') as f:
                            data = json.load(f)
                            results[bench_dir.name] = data
                    except Exception as e:
                        print(f"⚠️  Failed to load {json_file}: {e}")
                        
        return results
        
    def analyze_envelope_performance(self, results: Dict[str, Any]) -> None:
        """Analyze envelope operation performance"""
        print("\n📦 ENVELOPE OPERATIONS ANALYSIS")
        print("=" * 50)
        
        envelope_benches = {k: v for k, v in results.items() 
                           if 'envelope_operations' in k}
        
        if not envelope_benches:
            print("❌ No envelope benchmark results found")
            return
            
        for bench_name, data in envelope_benches.items():
            if 'mean' in data:
                mean_time = data['mean']['point_estimate']
                mean_time_ms = mean_time / 1_000_000  # Convert ns to ms
                
                print(f"🔍 {bench_name}")
                print(f"   Mean time: {mean_time_ms:.3f} ms")
                
                # Performance thresholds
                if 'create_envelope' in bench_name:
                    if mean_time_ms > 1.0:
                        print("   ⚠️  SLOW: Envelope creation > 1ms")
                    elif mean_time_ms < 0.1:
                        print("   ✅ FAST: Envelope creation < 0.1ms")
                        
                elif 'serialize' in bench_name:
                    if mean_time_ms > 5.0:
                        print("   ⚠️  SLOW: Serialization > 5ms")
                    elif mean_time_ms < 1.0:
                        print("   ✅ FAST: Serialization < 1ms")
                        
    def analyze_buffer_performance(self, results: Dict[str, Any]) -> None:
        """Analyze activity buffer performance"""
        print("\n💾 ACTIVITY BUFFER ANALYSIS")
        print("=" * 50)
        
        buffer_benches = {k: v for k, v in results.items() 
                         if 'activity_buffer' in k}
        
        if not buffer_benches:
            print("❌ No buffer benchmark results found")
            return
            
        memory_vs_persistent = {}
        
        for bench_name, data in buffer_benches.items():
            if 'mean' in data:
                mean_time = data['mean']['point_estimate']
                mean_time_us = mean_time / 1_000  # Convert ns to μs
                
                print(f"🔍 {bench_name}")
                print(f"   Mean time: {mean_time_us:.1f} μs")
                
                # Compare memory vs persistent performance
                if 'memory_buffer' in bench_name:
                    memory_vs_persistent['memory'] = mean_time_us
                elif 'persistent_buffer' in bench_name:
                    memory_vs_persistent['persistent'] = mean_time_us
                    
                # Performance thresholds
                if mean_time_us > 1000:  # 1ms
                    print("   ⚠️  SLOW: Buffer operation > 1ms")
                elif mean_time_us < 10:  # 10μs
                    print("   ✅ FAST: Buffer operation < 10μs")
                    
        # Compare memory vs persistent
        if 'memory' in memory_vs_persistent and 'persistent' in memory_vs_persistent:
            overhead = memory_vs_persistent['persistent'] / memory_vs_persistent['memory']
            print(f"\n📊 Persistent vs Memory Buffer:")
            print(f"   Persistent overhead: {overhead:.1f}x slower")
            if overhead > 10:
                print("   ⚠️  HIGH: Consider optimizing persistence layer")
            elif overhead < 3:
                print("   ✅ GOOD: Acceptable persistence overhead")
                
    def analyze_throughput(self, results: Dict[str, Any]) -> None:
        """Analyze message throughput performance"""
        print("\n⚡ THROUGHPUT ANALYSIS")
        print("=" * 50)
        
        throughput_benches = {k: v for k, v in results.items() 
                             if 'throughput' in k or 'message_processing' in k}
        
        if not throughput_benches:
            print("❌ No throughput benchmark results found")
            return
            
        for bench_name, data in throughput_benches.items():
            if 'mean' in data:
                mean_time = data['mean']['point_estimate']
                
                # Estimate messages per second (assuming 100 messages per benchmark)
                messages_per_iter = 100
                time_per_message = mean_time / messages_per_iter
                msgs_per_second = 1_000_000_000 / time_per_message  # ns to seconds
                
                print(f"🔍 {bench_name}")
                print(f"   Throughput: {msgs_per_second:.0f} messages/second")
                print(f"   Time per message: {time_per_message/1000:.1f} μs")
                
                # Performance thresholds
                if msgs_per_second < 1_000:
                    print("   ⚠️  LOW: < 1K messages/second")
                elif msgs_per_second > 10_000:
                    print("   ✅ HIGH: > 10K messages/second")
                else:
                    print("   ℹ️  MEDIUM: 1K-10K messages/second")
                    
    def analyze_memory_usage(self, results: Dict[str, Any]) -> None:
        """Analyze memory usage patterns"""
        print("\n🧠 MEMORY USAGE ANALYSIS")
        print("=" * 50)
        
        memory_benches = {k: v for k, v in results.items() 
                         if 'memory_usage' in k}
        
        if not memory_benches:
            print("❌ No memory benchmark results found")
            return
            
        for bench_name, data in memory_benches.items():
            if 'mean' in data:
                mean_time = data['mean']['point_estimate']
                mean_time_ms = mean_time / 1_000_000  # Convert ns to ms
                
                print(f"🔍 {bench_name}")
                print(f"   Allocation time: {mean_time_ms:.2f} ms")
                
                if 'envelope_memory' in bench_name:
                    # Estimate memory allocation rate (1000 envelopes)
                    envelopes_per_iter = 1000
                    time_per_envelope = mean_time / envelopes_per_iter
                    print(f"   Time per envelope: {time_per_envelope/1000:.1f} μs")
                    
                    if time_per_envelope > 100_000:  # 100μs per envelope
                        print("   ⚠️  SLOW: Memory allocation > 100μs per envelope")
                    elif time_per_envelope < 1_000:  # 1μs per envelope
                        print("   ✅ FAST: Memory allocation < 1μs per envelope")
                        
    def analyze_concurrency(self, results: Dict[str, Any]) -> None:
        """Analyze concurrent operation performance"""
        print("\n🔄 CONCURRENCY ANALYSIS")
        print("=" * 50)
        
        concurrent_benches = {k: v for k, v in results.items() 
                             if 'concurrency' in k}
        
        if not concurrent_benches:
            print("❌ No concurrency benchmark results found")
            return
            
        for bench_name, data in concurrent_benches.items():
            if 'mean' in data:
                mean_time = data['mean']['point_estimate']
                mean_time_ms = mean_time / 1_000_000  # Convert ns to ms
                
                print(f"🔍 {bench_name}")
                print(f"   Concurrent operation time: {mean_time_ms:.1f} ms")
                
                if 'concurrent_envelope' in bench_name:
                    # 100 concurrent tasks
                    tasks = 100
                    time_per_task = mean_time / tasks
                    print(f"   Time per concurrent task: {time_per_task/1000:.1f} μs")
                    
                    # Compare with theoretical sequential time
                    # (rough estimate based on envelope creation benchmarks)
                    estimated_sequential = tasks * 50_000  # 50μs per envelope (estimate)
                    speedup = estimated_sequential / mean_time
                    print(f"   Estimated concurrency speedup: {speedup:.1f}x")
                    
                    if speedup < 2:
                        print("   ⚠️  LOW: Poor concurrency scaling")
                    elif speedup > 10:
                        print("   ✅ EXCELLENT: Great concurrency scaling")
                    else:
                        print("   ℹ️  GOOD: Decent concurrency scaling")
                        
    def generate_recommendations(self, results: Dict[str, Any]) -> None:
        """Generate performance optimization recommendations"""
        print("\n💡 PERFORMANCE RECOMMENDATIONS")
        print("=" * 50)
        
        recommendations = []
        
        # Check envelope performance
        envelope_benches = [k for k in results.keys() if 'envelope' in k]
        if envelope_benches:
            envelope_times = [results[k].get('mean', {}).get('point_estimate', 0) 
                             for k in envelope_benches]
            avg_envelope_time = sum(envelope_times) / len(envelope_times) if envelope_times else 0
            
            if avg_envelope_time > 1_000_000:  # > 1ms
                recommendations.append(
                    "🔧 ENVELOPE: Consider optimizing envelope creation/serialization"
                )
                
        # Check buffer performance  
        buffer_benches = [k for k in results.keys() if 'buffer' in k]
        if buffer_benches:
            persistent_times = [results[k].get('mean', {}).get('point_estimate', 0) 
                               for k in buffer_benches if 'persistent' in k]
            if persistent_times and max(persistent_times) > 10_000_000:  # > 10ms
                recommendations.append(
                    "🔧 PERSISTENCE: Consider async I/O or batching for buffer persistence"
                )
                
        # Check memory patterns
        memory_benches = [k for k in results.keys() if 'memory' in k]
        if memory_benches:
            recommendations.append(
                "🔧 MEMORY: Profile heap allocations and consider object pooling"
            )
            
        # Check concurrency
        concurrent_benches = [k for k in results.keys() if 'concurrent' in k]
        if concurrent_benches:
            recommendations.append(
                "🔧 CONCURRENCY: Analyze lock contention and consider lock-free data structures"
            )
            
        if not recommendations:
            recommendations.append("✅ PERFORMANCE: All benchmarks show good performance characteristics")
            
        for rec in recommendations:
            print(f"   {rec}")
            
        print(f"\n📈 Run 'cargo bench --bench performance_benchmarks' to update results")
        print(f"📊 HTML reports available in: target/criterion/reports/index.html")
        
    def run_analysis(self) -> None:
        """Run complete performance analysis"""
        print("🚀 SW4RM Rust SDK Performance Analysis")
        print("=" * 60)
        
        results = self.load_benchmark_results()
        
        if not results:
            print("❌ No benchmark results found. Run benchmarks first:")
            print("   cargo bench --bench performance_benchmarks")
            return
            
        print(f"📊 Found {len(results)} benchmark results")
        
        # Run individual analyses
        self.analyze_envelope_performance(results)
        self.analyze_buffer_performance(results)
        self.analyze_throughput(results)
        self.analyze_memory_usage(results)
        self.analyze_concurrency(results)
        self.generate_recommendations(results)
        
        print("\n" + "=" * 60)
        print("✅ Performance analysis complete!")

def main():
    results_dir = sys.argv[1] if len(sys.argv) > 1 else "target/criterion"
    
    analyzer = PerformanceAnalyzer(results_dir)
    analyzer.run_analysis()

if __name__ == "__main__":
    main()