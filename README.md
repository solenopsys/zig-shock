

## SHOCK protocol (zig implementation)
 - S - Streaming 
 - H - High-speed 
 - O - Optimized (for) 
 - C - Cluster 
 - K - Kernel 


<div align="center">
  <img src="logo.svg" alt="SHOCK Protocol Logo" width="400"/>
</div>


<iframe width="720" height="480" src="https://www.youtube.com/embed/LhdJaWM2ykc" frameborder="0" allowfullscreen=""></iframe>


### Performance

```
zig run  src/bench.zig  
Build avg: 123.38 ns
Parse avg: 88.78 ns
Build/Parse ratio: 1.39x
```

```
zig run -O ReleaseFast  src/bench.zig 
Build avg: 69.75 ns
Parse avg: 11.82 ns
Build/Parse ratio: 5.90x
```

 ### Meta Header 2 bytes  
indicates the header structure and the length of the fields  

**First Byte:**  
- 1 bit — message size (1 or 2 bytes).  
- 1 bit — Next flag.  
- 2 bits — length of the message number in the stream (0–3 bytes). Supports up to 16 gigabytes with a message size of 1024.  
- 2 bits — length of the destination Object field (0–3 bytes).  
- 1 bit — length of the destination Method field (1 byte).  
- 1 bit — flag indicating the presence of the Second Byte.  

**Second Byte:**  
- 2 bits — length of the Session field (0–3 bytes).  
- 5 bits — length of the Process field (0–16 bytes).  
- 1 bit — reserved (can be used in long streams over 16 gigabytes or in processes).

