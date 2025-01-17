import pvporcupine
from pvrecorder import PvRecorder
import os

print("Available wake words:")
print("-------------------")
print("\n".join(pvporcupine.KEYWORDS))
print("\n")

access_key = os.getenv('PICOVOICE_ACCESS_KEY')
keywords = ['alexa']  
sensitivity = 0.8

porcupine = pvporcupine.create(access_key, keywords=keywords, sensitivities=[sensitivity])
recoder = PvRecorder(
    device_index=-1,
    frame_length=porcupine.frame_length
)

recoder.start()
print(f"Listening for wake word: {keywords[0]} (sensitivity: {sensitivity})")

try:
    while True:        
        keyword_index = porcupine.process(recoder.read())        
        if keyword_index >= 0:            
            print(f"Detected {keywords[keyword_index]}")

except KeyboardInterrupt:    
    recoder.stop()
finally:
    porcupine.delete()    
    recoder.delete()


