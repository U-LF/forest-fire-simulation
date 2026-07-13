import os
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, classification_report
import time
import joblib

try:
    import tensorflow as tf
except ImportError:
    print("TensorFlow is not installed. Please install it to parse .tfrecord files.")
    print("Run: pip install tensorflow")
    exit(1)

# The list of feature names in the dataset
FEATURE_NAMES = [
    'elevation', 'pdsi', 'NDVI', 'pr', 'sph', 'th', 'tmmn', 'tmmx', 'vs', 'erc',
    'population', 'PrevFireMask'
]

# The target variable name
TARGET_NAME = 'FireMask'

def _parse_function(example_proto):
    """Parses a single tf.Example into a dictionary of tensors."""
    feature_description = {
        f: tf.io.FixedLenFeature([64, 64], tf.float32) for f in FEATURE_NAMES
    }
    feature_description[TARGET_NAME] = tf.io.FixedLenFeature([64, 64], tf.float32)
    
    return tf.io.parse_single_example(example_proto, feature_description)

def load_dataset(pattern, batch_size=64):
    """Loads and parses the dataset from tfrecord files."""
    files = tf.data.Dataset.list_files(pattern)
    dataset = files.interleave(tf.data.TFRecordDataset, cycle_length=4, num_parallel_calls=tf.data.AUTOTUNE)
    dataset = dataset.map(_parse_function, num_parallel_calls=tf.data.AUTOTUNE)
    dataset = dataset.batch(batch_size)
    dataset = dataset.prefetch(tf.data.AUTOTUNE)
    return dataset

def flatten_to_tabular(batch_dict):
    """
    Takes a batch of 64x64 grids (a dictionary of feature arrays) and flattens them 
    into a tabular pandas DataFrame, calculating neighborhood states for 'prev_fire_mask'.
    """
    rows = []
    
    # Extract arrays from the tensor dictionary
    # batch_dict[key] has shape (batch_size, 64, 64)
    batch_size = batch_dict['PrevFireMask'].shape[0]
    
    prev_fire_mask = batch_dict['PrevFireMask'].numpy()
    target_mask = batch_dict[TARGET_NAME].numpy()
    
    # Extract static/environmental features
    env_features = {f: batch_dict[f].numpy() for f in FEATURE_NAMES if f != 'PrevFireMask'}
    
    for b in range(batch_size):
        # We only look at pixels where there's valid data. 
        # Sometimes satellite data has gaps or no-data values. We'll ignore edge pixels for neighbor logic.
        for i in range(1, 63):
            for j in range(1, 63):
                # If the cell is ALREADY burning, we typically aren't predicting if it *ignites*
                if prev_fire_mask[b, i, j] > 0:
                    continue
                
                # Calculate neighbors (1.0 means fire, 0.0 means no fire)
                fire_north = prev_fire_mask[b, i-1, j]
                fire_south = prev_fire_mask[b, i+1, j]
                fire_east  = prev_fire_mask[b, i, j+1]
                fire_west  = prev_fire_mask[b, i, j-1]
                total_burning_neighbors = fire_north + fire_south + fire_east + fire_west
                
                # To balance the massive dataset, aggressively downsample non-burning, safe cells
                if total_burning_neighbors == 0 and np.random.rand() > 0.01:
                    continue
                
                # Target is whether it catches fire (1.0) or not (0.0 or -1 for no-data)
                target = target_mask[b, i, j]
                if target < 0: # Usually -1 means no data in this dataset
                    continue
                
                row = {
                    'fire_north': fire_north,
                    'fire_south': fire_south,
                    'fire_east': fire_east,
                    'fire_west': fire_west,
                    'total_burning_neighbors': total_burning_neighbors,
                    'target_catches_fire': 1 if target > 0 else 0
                }
                
                for f, array in env_features.items():
                    row[f] = array[b, i, j]
                    
                rows.append(row)
                
    return pd.DataFrame(rows)

def train_on_real_data():
    data_dir = os.path.join(os.path.dirname(__file__), 'data')
    train_pattern = os.path.join(data_dir, '*train*.tfrecord')
    test_pattern = os.path.join(data_dir, '*test*.tfrecord')
    
    print("Loading datasets...")
    # Load just a small subset for a quick test (e.g., 2 batches)
    train_dataset = load_dataset(train_pattern, batch_size=32).take(10)
    test_dataset = load_dataset(test_pattern, batch_size=32).take(2)
    
    print("Processing training data...")
    train_dfs = []
    for batch in train_dataset:
        train_dfs.append(flatten_to_tabular(batch))
    train_df = pd.concat(train_dfs, ignore_index=True)
    
    print("Processing testing data...")
    test_dfs = []
    for batch in test_dataset:
        test_dfs.append(flatten_to_tabular(batch))
    test_df = pd.concat(test_dfs, ignore_index=True)
    
    print(f"Train samples: {len(train_df)}, Test samples: {len(test_df)}")
    
    X_train = train_df.drop(columns=['target_catches_fire'])
    y_train = train_df['target_catches_fire']
    X_test = test_df.drop(columns=['target_catches_fire'])
    y_test = test_df['target_catches_fire']
    
    print("\n--- Training Logistic Regression on Real Satellite Data ---")
    start_time_lr = time.time()
    lr_model = LogisticRegression(max_iter=1000, n_jobs=-1)
    lr_model.fit(X_train, y_train)
    lr_preds = lr_model.predict(X_test)
    
    print(f"Training took: {time.time() - start_time_lr:.3f} seconds")
    print(f"Accuracy: {accuracy_score(y_test, lr_preds):.4f}")
    
    print("\nLogistic Regression Coefficients:")
    coef_df = pd.DataFrame({'Feature': X_train.columns, 'Coefficient': lr_model.coef_[0]})
    print(coef_df.sort_values(by='Coefficient', ascending=False))
    
    lr_model_path = os.path.join(os.path.dirname(__file__), 'logistic_regression_model.joblib')
    joblib.dump(lr_model, lr_model_path)
    print(f"\nLogistic Regression Model successfully saved to: {lr_model_path}")
    
    print("\n--- Training Random Forest on Real Satellite Data ---")
    start_time = time.time()
    rf_model = RandomForestClassifier(n_estimators=100, max_depth=12, random_state=42, n_jobs=-1)
    rf_model.fit(X_train, y_train)
    rf_preds = rf_model.predict(X_test)
    
    print(f"Training took: {time.time() - start_time:.3f} seconds")
    print(f"Accuracy: {accuracy_score(y_test, rf_preds):.4f}")
    
    # Print Feature Importances
    print("\nFeature Importances (What the model learned from real satellite data):")
    imp_df = pd.DataFrame({'Feature': X_train.columns, 'Importance': rf_model.feature_importances_})
    print(imp_df.sort_values(by='Importance', ascending=False))
    
    # Save the model to disk
    model_path = os.path.join(os.path.dirname(__file__), 'random_forest_model.joblib')
    joblib.dump(rf_model, model_path)
    print(f"\nModel successfully saved to: {model_path}")

if __name__ == "__main__":
    train_on_real_data()
