import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
plt.rcParams.update({"font.size":8,"font.family":"DejaVu Sans","axes.spines.top":False,"axes.spines.right":False})
# bits per (real or imaginary) value, 50 frames, 4 RX, from the Stage 2 compression ratios
lab=["int16\ncontainer","occupied\nrange","Huffman coding\n(no prediction)","+ prediction","+ re-derived\ndictionary"]
drhe=[16.0, 9.77, 16/3.479, 16/3.751, 16/4.218]
lpc =[None, None, None,     16/3.697, 16/4.404]
fig,ax=plt.subplots(figsize=(6.2,2.9))
cols=["#33414f","#6b7b8c","#40607d","#2f6d4f","#7aa33b"]
w=0.36
for i,v in enumerate(drhe):
    if lpc[i] is None:
        ax.bar(i,v,width=0.6,color=cols[i],zorder=3); ax.text(i,v+0.3,f"{v:.2f}",ha="center",fontsize=7.5)
    else:
        ax.bar(i-w/2,v,width=w,color=cols[i],zorder=3,label="DRHE" if i==3 else None)
        ax.bar(i+w/2,lpc[i],width=w,color=cols[i],alpha=0.55,hatch="//",edgecolor="white",zorder=3,label="LPC" if i==3 else None)
        ax.text(i-w/2,v+0.3,f"{v:.2f}",ha="center",fontsize=7); ax.text(i+w/2,lpc[i]+0.3,f"{lpc[i]:.2f}",ha="center",fontsize=7)
for i in range(1,5):
    prev=drhe[i-1]; cur=drhe[i]
    ax.annotate(f"$\\div${prev/cur:.2f}",(i-0.5,(prev+cur)/2),ha="center",fontsize=7,color="0.3")
ax.set_xticks(range(5)); ax.set_xticklabels(lab,fontsize=7.5)
ax.set_ylabel("bits per value"); ax.set_ylim(0,18); ax.grid(axis="y",lw=0.4,color="0.85",zorder=0)
ax.legend(frameon=False,fontsize=7.5,loc="upper right")
fig.tight_layout(pad=0.4); fig.savefig("fig_bits.pdf"); print("ok")
