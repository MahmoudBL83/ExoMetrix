# ExoMetrix Demo Presentation Script

## Slide 1: Title Slide
**Title:** ExoMetrix: Next-Generation Kinematic Tracking and Rehabilitation
**Visual:** The ExoMetrix logo and a visually appealing graphic of the app.
**Speaker Notes:**
"Hello everyone, and welcome to our demonstration of ExoMetrix. ExoMetrix is an innovative, dual-interface platform designed to bridge the gap between patient rehabilitation and clinical monitoring using real-time kinematic tracking and AI-driven insights. Today, I'm excited to walk you through our live demo and show how we're transforming physical therapy."

---

## Slide 2: The Core Problem & Solution
**Title:** The Challenge in Physical Therapy
**Visual:** High-level bullet points comparing traditional therapy with ExoMetrix's smart connected approach.
**Speaker Notes:**
"In traditional physical therapy, clinicians often struggle to get objective, real-time data on a patient's movement outside of the clinic. Patients, on the other hand, can lose motivation or unknowingly perform exercises incorrectly, leading to 'compensatory' movements. 
ExoMetrix solves this. By using a wearable Bluetooth Low Energy (BLE) sensor—specifically tracking knee angles—our app connects directly to the patient's phone to provide realtime feedback, while streaming the exact same telemetry to the clinician's dashboard."

---

## Slide 3: Live Demo Setup & Bluetooth Connectivity
**Title:** Seamless Hardware Integration
**Visual:** Screenshot of the Bluetooth scanning modal in the app.
**Speaker Notes:**
"Let's dive into the app. The core of ExoMetrix is its seamless Bluetooth integration. From the Patient Dashboard, users can simply tap 'Scan' to discover nearby BLE medical devices. 
For today’s demonstration, if we don't have the physical hardware attached, the app features a robust 'Mock Mode'. When enabled, Mock Mode injects realistic, simulated knee-swing angles, complete with micro-variances and occasional bad steps to demonstrate how our system evaluates anomalous behavior."

---

## Slide 4: The Patient Dashboard - Gamifying Rehab
**Title:** Engaging the Patient
**Visual:** Video or Series of screenshots of the Patient Dashboard (Stick figure, Score card, AI Feedback).
**Speaker Notes:**
"Here is the Patient Dashboard, engineered to keep the user motivated and informed. 
Notice the gamified elements. As the patient moves, the animated stick figure provides a live mirror of their knee angle in real-time. 
Every step is evaluated by our AI backend. If they perform the movement optimally—keeping the angle within the target window—they earn 10 points, and the UI glows with a positive green 'Good step' indicator. If they use a compensatory, incorrect movement, they lose 5 points, and an orange warning appears. They also see their total steps analyzed and their active session time, turning a tedious exercise into an engaging, goal-oriented activity."

---

## Slide 5: The AI Backend & Predictive Analytics
**Title:** Smart Evaluation
**Visual:** Architecture diagram showing Flutter app -> Next.js/Python AI API.
**Speaker Notes:**
"But how does the app know if a step is good or bad? 
Under the hood, ExoMetrix communicates with a predictive API. Every second, the real-time angle data is sent to our backend engine. The AI evaluates the kinematic data and classifies the step. Furthermore, it dynamically calculates a 'Mechanical Assist' percentage—predicting exactly how much robotic or physical assistance the joint needs based on the severity of the deviation."

---

## Slide 6: The Clinician Dashboard - Data-Driven Insights
**Title:** Empowering the Clinician
**Visual:** Clinician Dashboard screenshot showing the Knee Angle Log chart and KPI grid.
**Speaker Notes:**
"Now let's switch hats and look at what the physical therapist sees on the Clinician Dashboard. 
Instead of gamification, the clinician sees raw, actionable data. 
- The **Knee Angle Log** provides a live, continuously updating line chart of the patient’s joint flexion. 
- Below the chart, we have four critical KPIs:
  1. The **Stability Score**, indicating overall risk level.
  2. The **Mechanical Assist** prediction from our AI.
  3. The exact count of **Good Steps (Target adherence)**.
  4. The count of **Compensations**, allowing the clinician to immediately identify if the therapy needs to be scaled back or adjusted."

---

## Slide 7: Conclusion & Future Outlook
**Title:** The Future of Movement Tracking
**Visual:** A powerful summary graphic.
**Speaker Notes:**
"To summarize, ExoMetrix is a complete end-to-end prototype. From local Bluetooth hardware integration to a dual-sided Flutter UI, and powered by an intelligent prediction API, it proves that the future of physical therapy is digital, data-driven, and highly engaging. 
Thank you for your time, and we'd love to answer any questions or let you try the mock mode yourself."
