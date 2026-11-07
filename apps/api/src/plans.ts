export const plans = [
  {
    id: "normal",
    name: "Normal",
    priceInPaise: 300000,
    currency: "INR",
    durationMonths: 1,
    videoSessions: 0,
    features: [
      "Stored exercise demonstrations",
      "AI coaching chat",
      "Personalized workout planning",
      "Nutrition, habits and progress tracking",
    ],
  },
  {
    id: "premium",
    name: "Premium",
    priceInPaise: 1000000,
    currency: "INR",
    durationMonths: 1,
    videoSessions: 10,
    features: ["All Normal features", "10 live video coaching sessions"],
  },
  {
    id: "premium-plus",
    name: "Premium Plus",
    priceInPaise: 2000000,
    currency: "INR",
    durationMonths: 1,
    videoSessions: 25,
    features: [
      "All lower-plan features",
      "25 live video coaching sessions in total",
    ],
  },
] as const;
