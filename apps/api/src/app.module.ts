import { Controller, Get, Module } from "@nestjs/common";
import { plans } from "./plans";
import { StoreService, StoreController, CartController, StoreAdminController, CustomerStoreOrdersController } from './store';
import { TrainerMessageController, TrainerMessageService } from './trainer-messages';
import { Database } from "./database";
import { HabitController, HabitService } from './habits';
import { NutritionController, NutritionService } from './nutrition';
import { NutritionProvider } from './nutrition-provider';
import { MealEstimateController, MealEstimateService } from './meal-estimates';
import { MealEstimateProvider } from './meal-estimate-provider';
import { BodyProgressController, BodyProgressService } from './body-progress';
import { AiPlanningController, AiPlanningService, AiPlanningWorker } from './ai-planning';
import { AiPlanningProvider } from './ai-planning-provider';
import { CoachingController, CoachingService } from './coaching';
import { CoachingProvider } from './coaching-provider';
import { StaffController, StaffService, TrainerFeedbackController } from './staff';
import { CustomerSessionsController, StaffSessionsController, SessionService } from './sessions';
import { SessionPolicyService, SessionVideoProvider } from './session-policy';
import { MembershipService, MembershipController } from "./memberships";
import {
  WorkoutService,
  WorkoutController,
  ExerciseController,
} from "./workouts";
import {
  ExerciseMedia,
  PlaybackController,
  MediaController,
} from "./exercise-media";
import {
  AuthController,
  ProfileController,
  CoachController,
  AuthService,
  AuthGuard,
  AuthThrottle,
} from "./auth";
@Controller()
class AppController {
  @Get("health")
  health() {
    return {
      status: "ok",
      service: "jbfitness-api",
      stage: "membership_foundation",
    };
  }
  @Get("plans")
  getPlans() {
    return { plans, checkoutEnabled: false, audioCalls: "deferred" };
  }
}
@Module({
  controllers: [
    StoreController, CartController, StoreAdminController, CustomerStoreOrdersController,
    TrainerMessageController,
    AppController,
    HabitController,
    NutritionController,
    MealEstimateController,
    BodyProgressController,
    AiPlanningController,
    CoachingController,
    StaffController,
    TrainerFeedbackController,
    CustomerSessionsController,
    StaffSessionsController,
    AuthController,
    ProfileController,
    CoachController,
    MembershipController,
    WorkoutController,
    ExerciseController,
    PlaybackController,
    MediaController,
  ],
  providers: [
    StoreService,
    TrainerMessageService,
    Database,
    HabitService,
    NutritionService,
    NutritionProvider,
    MealEstimateService,
    MealEstimateProvider,
    BodyProgressService,
    AiPlanningService,
    AiPlanningProvider,
    AiPlanningWorker,
    CoachingService,
    CoachingProvider,
    StaffService,
    SessionService,
    SessionPolicyService,
    SessionVideoProvider,
    AuthService,
    AuthGuard,
    AuthThrottle,
    MembershipService,
    WorkoutService,
    ExerciseMedia,
  ],
})
export class AppModule {}
