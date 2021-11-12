library(tidymodels)
library(skimr)

train<-read.csv("train.csv",sep = ",")
test<-read.csv("test.csv",sep = ",")

skim(train)
skim(test)

train$subscribed<-ifelse(train$subscribed == 0,"NO","YES")
train<-train %>% select(-customer_id) %>% 
        mutate_if(is.character,factor)
str(train)
train %>% group_by(subscribed) %>%
        summarise(n())

#model


##splits

train_split<-initial_split(train,strata = subscribed)
trainY<-training(train_split)
testY<-testing(train_split)

##cross validation folds

folds<-vfold_cv(trainY)
folds

##recipe
library(themis)
rec<-recipe(subscribed ~ ., data = trainY) %>% 
        step_dummy(all_nominal(), - subscribed) %>%
        step_smote(subscribed)
wf<-workflow() %>% 
        add_recipe(rec)

glr_spec<-logistic_reg() %>%
        set_engine("glm")

rf_spec<- rand_forest(trees = 1000) %>%
        set_engine("ranger") %>%
        set_mode("classification")

doParallel::registerDoParallel()
glm_res<-wf %>% add_model(glr_spec) %>%
        fit_resamples(
                resample = folds,
                metrics = metric_set(roc_auc,accuracy,specificity,sensitivity),
                control = control_resamples(save_pred = TRUE)
        )

rf_res<-wf %>% add_model(rf_spec) %>%
        fit_resamples(
                resample = folds,
                metrics = metric_set(roc_auc,accuracy,specificity,sensitivity),
                control = control_resamples(save_pred = TRUE)
        )
collect_metrics(glm_res)
collect_metrics(rf_res)

glm_res %>% conf_mat_resampled()
rf_res %>% conf_mat_resampled()

rf_res %>%
        collect_predictions() %>%
        group_by(id) %>%
        roc_curve(subscribed,.pred_YES) %>%
        autoplot()


glm_res %>%
        collect_predictions() %>%
        group_by(id) %>%
        roc_curve(subscribed,.pred_YES) %>%
        autoplot()

rf_wf<- workflow() %>% 
        add_formula(subscribed ~ .) %>%
        add_model(rf_spec)

final_fit<-wf %>% 
        add_model(rf_spec) %>%
        last_fit(train_split)


collect_metrics(final)

collect_predictions(final) %>%
        conf_mat(subscribed,.pred_class)

library(vip)

rf_wf %>% fit(data = trainY) %>%
        extract_fit_parsnip() %>% vip(geom = "point")
#test data


customer_id<-test %>% 
        select(customer_id)

test<-test %>% 
        select(-customer_id) %>%
        mutate_if(is.character,factor)

test_result<- rf_wf %>% fit(data = train) %>%
        predict(new_data = test)

test_df<-data.frame(id = customer_id,outcome = test_result$.pred_class)
write.csv(test_df,"result.csv",row.names = FALSE)
