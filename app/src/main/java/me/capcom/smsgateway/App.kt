package me.capcom.smsgateway

import android.app.Application
import android.content.Context
import healthModule
import me.capcom.smsgateway.data.dbModule
import me.capcom.smsgateway.helpers.LocaleHelper
import me.capcom.smsgateway.modules.connection.connectionModule
import me.capcom.smsgateway.modules.encryption.encryptionModule
import me.capcom.smsgateway.modules.events.eventBusModule
import me.capcom.smsgateway.modules.incoming.incomingModule
import me.capcom.smsgateway.modules.localserver.localserverModule
import me.capcom.smsgateway.modules.logs.logsModule
import me.capcom.smsgateway.modules.messages.messagesModule
import me.capcom.smsgateway.modules.mms.mmsModule
import me.capcom.smsgateway.modules.notifications.notificationsModule
import me.capcom.smsgateway.modules.orchestrator.OrchestratorService
import me.capcom.smsgateway.modules.orchestrator.orchestratorModule
import me.capcom.smsgateway.modules.ping.pingModule
import me.capcom.smsgateway.modules.receiver.receiverModule
import me.capcom.smsgateway.modules.settings.settingsModule
import me.capcom.smsgateway.modules.webhooks.webhooksModule
import org.koin.android.ext.android.get
import org.koin.android.ext.android.inject
import org.koin.android.ext.koin.androidContext
import org.koin.android.ext.koin.androidLogger
import org.koin.core.context.startKoin

class App: Application() {
    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base?.let { LocaleHelper.onAttach(it) })
    }

    override fun onCreate() {
        super.onCreate()

        startKoin {
            androidLogger()
            androidContext(this@App)
            modules(
                eventBusModule,
                settingsModule,
                dbModule,
                logsModule,
                notificationsModule,
                mmsModule,
                messagesModule,
                incomingModule,
                receiverModule,
                encryptionModule,
                healthModule,
                webhooksModule,
                localserverModule,
                pingModule,
                connectionModule,
                orchestratorModule,
            )
        }

        Thread.setDefaultUncaughtExceptionHandler(
            GlobalExceptionHandler(
                Thread.getDefaultUncaughtExceptionHandler()!!,
                get()
            )
        )

        instance = this

        get<OrchestratorService>().start(this, true)
    }

    companion object {
        lateinit var instance: App
            private set
    }
}
