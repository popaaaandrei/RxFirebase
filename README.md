# RxFirebase
These are some RxSwift wrappers for Firebase methods. It uses the latest Firebase API.

My initial intention was to create a CocoaPod for this with RxSwift and Firebase as dependencies but I didn't manage to do this. If you want to improve this code and help transition to a proper Pod, good luck using `vendored_frameworks` when creating the `podspec` :) Meanwhile just copy-paste or drop the swift file inside your project.

## Typical usage

This implementation provides `Firebase` as a singleton from which you can call particular actions. 

#### 1) first add Firebase & RxSwift, and setup Firebase in your project
I for example use the following Pods:

```
pod 'Firebase'
pod 'Firebase/Auth'
pod 'Firebase/Database'
pod 'Firebase/Storage'

pod 'RxSwift'
pod 'RxCocoa'
```

#### 2) subscribe to `rx_user` in `didFinishLaunchingWithOptions`

```
Firebase
	.instance
	.rx_user
	.subscribeNext { [weak self] user in
		if let user = user {
			// logged in
			self?.showMainInterface()
		} else {
			// logged out
			self?.showLogin()
		}
	}
	.addDisposableTo(disposeBag)
```

#### 2) begin using the provided `Observables` or implement your own ones for your models

You can also check my [article](https://alt-tab.ghost.io/protocol-extensions-model/) on protocol extensions and how they can be used to simplify adding behaviour to your models.


```
* Firebase.instance.rx_currentUser()
* Firebase.instance.rx_authStateDidChange()
* Firebase.instance.rx_signInWithEmail(email: String, password: String)
* Firebase.instance.rx_signInWithCredential(credential: FIRAuthCredential)
* Firebase.instance.rx_sendPasswordResetWithEmail(email: String)
* Firebase.instance.rx_createUser(email: String, password: String)
* Firebase.instance.rx_publish(object: AnyObject, atPath: String)
```

```
guard let database = Firebase.instance.database else {
	print("you don't have access to the database :), check your auth")
	return
}

database.root.child("your_path").rx_setValue(object: AnyObject, autoId: Bool = false)
database.root.child("your_path").rx_observe(eventType: FIRDataEventType = .Value)
database.root.child("your_path").rx_observeSingleEventOfType(eventType: FIRDataEventType = .Value)
```

```
guard let storage = Firebase.instance.storage else {
	print("you don't have access to the storage :), check your auth")
	return
}

storage.root().child("your_path").rx_putJPEG(image: UIImage, compressionQuality: CGFloat = 1)
storage.root().child("your_path").rx_putData(withData withData: NSData, metadata: FIRStorageMetadata? = nil)
storage.root().child("your_path").rx_downloadData(maxSize: Int64 = 1024 * 1024)
storage.root().child("your_path").rx_downloadImage()
storage.root().child("your_path").rx_downloadTo(url url: NSURL)
```

As usual, if any of you has something to say, please create a new issue and we'll update the code together.
Don't forget to have fun! :]

XO,
Andrei
@popaaaandrei